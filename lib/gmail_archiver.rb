require 'sequel'
require 'gmail_archiver/imap_client'

DB = Sequel.connect 'postgres:///gmail'

require 'gmail_archiver/database'
require 'yaml'


class GmailArchiver

  def self.run(start_idx=1)
    # THIS FOR TESTING ONLY
    config = YAML::load File.read(File.expand_path('vmailrc'))
    imap_client = GmailArchiver::ImapClient.new(config)

    imap_client.with_open do 
      ['INBOX', '[Gmail]/Important'].each do |mailbox|

        label = Label[name: mailbox] || Label.create(name: mailbox) 

        imap_client.select_mailbox mailbox

        get_messages(imap_client.imap, start_idx) do |x|

          # TODO get headers first and check if message-id is in db
          # If not, then download the RFC822

          text = x.message
          text = text.encode("UTF-8", undef: :replace, invalid: :replace)

          next if x.date.nil?

          params = {message_id: x.message_id,
            date: x.date,
            subject: x.subject, 
            seen: x.flags.include?(:Seen),
            in_reply_to: x.in_reply_to,
            text: text,
            rfc822: x.rfc822.encode("UTF-8", undef: :replace, invalid: :replace),
            size: x.size } 

          begin

            mail = GmailArchiver::Mail[message_id: x.message_id]
            if mail 
              # Just make sure the mail is labeled
              if !Labeling[mail_id: mail.mail_id, label_id: label.label_id]
                Labeling.create(mail_id: mail.mail_id, label_id: label.label_id)
              end
              next
            end

            begin
              mail = GmailArchiver::Mail.create params
            rescue
              [:text, :rfc822].each do |x|
                params[x] = params[x].encode("US-ASCII", undef: :replace, invalid: :replace)
                mail = GmailArchiver::Mail.create params
              end
            end

            DB[:labelings].insert(mail_id: mail.mail_id, label_id: label.label_id)

            %w(from to cc).each do |f|
              xs = x.mail[f]
              next if xs.nil?
              if xs.respond_to?(:addrs)
                xs = xs.addrs
              end
              [xs].flatten.
              map {|a| 
                a.respond_to?(:addrs) ? a.addrs : a
              }.flatten.each do |address|
                parse_email_address(address, f, mail)
              end
            end

          rescue
            puts params.inspect
            raise
          end

        end
      end
    end
  end

  def self.get_messages(imap, start_idx=1)
    res = imap.fetch([start_idx,"*"], ["ENVELOPE"])
    max_seqno = res ? res[-1].seqno : 1
    puts "Max seqno: #{max_seqno}"
    range = (start_idx..max_seqno)
    range.to_a.each_slice(30) do |id_set|
      # use bounds instead of specifying all indexes
      bounds = Range.new(id_set[0], id_set[-1], false) # nonexclusive
      puts "Fetching slice: #{bounds}"
      imap.fetch(bounds, ["FLAGS", 'ENVELOPE', 'RFC822', 'RFC822.SIZE']).each do |x|
        yield FetchData.new(x)
      end
    end
  end

  def self.parse_email_address(x, f, mail)
    if (x.respond_to?(:value)) && (v = x.value) && v =~ /@/
      v.split(/, +/).map {|w| parse_email_address(w, f, mail)}
      return
    end
    res = if x.respond_to?(:mailbox)
      [x.name, "%s@%s" % [x.mailbox, x.host]]
    elsif x.respond_to?(:address)
      [x.name, x.address]
    elsif x.is_a?(String)
      if x[/<([^>\s]+)>/, 1]   # email address and name
        email = x[/<([^>\s]+)>/, 1]
        name = x[/^[^<\s]+/, 0]
        [name, email]
      else
        [nil, x]
      end
    end
    n, e = *res
    unless e
      puts "No email found for #{n}"
      return
    end
    save_contact(e, n, f, mail)
  end

  # e email
  # n name
  # f field type
  def self.save_contact(e, n, f, mail)
    begin
      if (contact = Contact.filter(email: e).first).nil?
        contact = Contact.create(email: e, name: n)
        # puts "Created contact: #{contact}"
      elsif (n && (contact = Contact.filter(email: e, name: n).first)) || 
        (n.nil? && (contact = Contact.filter(email: e).first)) 
        # puts "Reusing contact (exact match): #{contact}"
      elsif n && (contact = Contact.filter("email = ? and (name != ? or name is null)", e, n).first)
        old_version = contact.to_s
        if contact.name.nil? || (n.length > contact.name.length)
          contact.update name: n
          # puts "Updating and reusing contact: #{old_version} => #{contact}"
        else
          # puts "Reusing contact (partial match, old version preserved): #{old_version} > #{n}"
        end
      else
        raise "Save Contact Error"
      end
      p = {contact_id: contact.contact_id,
           mail_id: mail.mail_id,
           connection: f}
      if f == 'from'
        puts "Created mail: #{mail.date.strftime("%m-%d-%Y")} | #{contact} | #{mail.subject && mail.subject[0,50]}"
        mail.update(sender_id: contact.contact_id)
      elsif !DB[:connections].filter(p).first
        DB[:connections].insert p
      end
    rescue Sequel::Error
      puts "ERROR. #{$!}"
      puts "email_address: #{e}"
      puts "name: #{n}"
      raise
    end
  end
end

if __FILE__ == $0
  start_idx = (ARGV[0] || 1).to_i
  GmailArchiver.run start_idx
end

