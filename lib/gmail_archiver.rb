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
          #

          text = x.message
          text = Iconv.conv("UTF-8//IGNORE", 'UTF-8', text)

          next if x.date.nil?

          params = {message_id: x.message_id,
            date: x.date,
            subject: x.subject, 
            seen: x.flags.include?(:Seen),
            in_reply_to: x.in_reply_to,
            text: text,
            rfc822: (Iconv.conv("UTF-8//IGNORE", 'UTF-8', x.rfc822)),
            size: x.size } 
          sender_params = { email: parse_email_address(x.sender)[1] }

          begin
            if !(sender = Contact[email: sender_params[:email]])
              sender = Contact.create(email: sender_params[:email])
            end

            mail = GmailArchiver::Mail[message_id: x.message_id]
            if mail 
              # Just make sure the mail is labeled
              if !Labeling[mail_id: mail.mail_id, label_id: label.label_id]
                Labeling.create(mail_id: mail.mail_id, label_id: label.label_id)
              end
              next
            end

            mail = GmailArchiver::Mail.create params.merge(sender_id: sender.contact_id)
            puts "Created mail  #{mail.date.strftime("%m-%d-%Y")}  #{mail.subject && mail.subject[0,50]}"

            DB[:labelings].insert(mail_id: mail.mail_id, label_id: label.label_id)

            %w(to cc).each do |f|
              xs = x.mail[f]
              next if xs.nil?
              if xs.respond_to?(:addrs)
                xs = xs.addrs
              end
              [xs].flatten.
              map {|a| 
                a.respond_to?(:addrs) ? a.addrs : a
              }.flatten.each do |address|
                n, e = *parse_email_address(address)
                next unless e
                if e.is_a?(Array) # array of email addresses; no names
                  e.map {|e2| 
                    save_contact(e2.to_s, n, f, mail) 
                  }
                else
                  n = address.name
                  save_contact(e, n, f, mail)
                end
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

  def self.parse_email_address(x)
    if x.respond_to?(:mailbox)
      [x.name, "%s@%s" % [x.mailbox, x.host]]
    elsif x.respond_to?(:address)
      [x.name, x.address]
    elsif x.is_a?(String)
      if x[/<([^>\s]+)>/, 1]   # email address and name
        email = x[/<([^>\s]+)>/, 1]
        name = x[/^[^>\s]+/, 0]
        [name, email]
      else
        [nil, x]
      end
    elsif (x.respond_to?(:value)) && (v = x.value) && v =~ /@/
      v.split(/, +/).map {|w| parse_email_address(w)}
    end
  end

  # e email
  # n name
  # f field type
  def self.save_contact(e, n, f, mail)
    begin
      if !(contact = Contact[email: e, name: n])
        contact = Contact.create(email: e, name: n)
        puts "Created contact  #{e}"
      end
      p = {contact_id: contact.contact_id,
           mail_id: mail.mail_id,
           connection: f}
      if !DB[:connections].filter(p).first
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

