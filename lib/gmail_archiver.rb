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

        $mailbox = mailbox

        label = Label[name: mailbox] || Label.create(name: mailbox) 

        imap_client.select_mailbox mailbox

        get_messages(imap_client, start_idx) do |x|

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
                # TODO add logging here
                Labeling.create(mail_id: mail.mail_id, label_id: label.label_id)
              end
              next
            end

            begin
              mail = GmailArchiver::Mail.create params
            rescue
              [:text, :rfc822].each do |x|
                params[x] = params[x].encode("US-ASCII", undef: :replace, invalid: :replace)
              end
              mail = GmailArchiver::Mail.create params
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

  def self.get_messages(imap_client, start_idx=1)
    imap = imap_client.imap
    res = imap.fetch([start_idx,"*"], ["ENVELOPE"])
    max_seqno = res ? res[-1].seqno : 1
    puts "Max seqno: #{max_seqno}"
    range = (start_idx..max_seqno)
    range.to_a.each_slice(30) do |id_set|
      # use bounds instead of specifying all indexes
      bounds = Range.new(id_set[0], id_set[-1], false) # nonexclusive
      puts "Fetching slice: #{bounds}"
      begin
        imap.fetch(bounds, ["FLAGS", 'ENVELOPE', 'RFC822', 'RFC822.SIZE']).each do |x|
          yield FetchData.new(x)
        end
      rescue 
        if $!.message =~ /unknown token/ # this is an unfetchable (by Ruby Net::IMAP) message
          puts "Encountered an error: #{$!}.\n#{$!.backtrace.join("\n")}\nRetrying individual messages."
          imap_client.reopen
          imap = imap_client.imap
          bounds.each {|i|
            begin
              imap.fetch(i, ["FLAGS", 'ENVELOPE', 'RFC822', 'RFC822.SIZE']).each { |x| yield FetchData.new(x) }
            rescue
              puts "Problem fetching message: #{i}: #{$!}. Skipping."
              imap_client.reopen
              imap = imap_client.imap
            end
          }
        else
          raise
        end
      end
    end
  end

  def self.parse_email_address(x, f, mail)
    if x.respond_to?(:[]) && x[f.to_s] && x[f.to_s].respond_to(:formatted)
      x[f.to_s].formatted.map {|w| 
        puts "Formatted field : #{w}"
        parse_email_address(w, f, mail)
      }
      return
    end
    res = if x.respond_to?(:mailbox)
      [x.name.decoded, "%s@%s" % [x.mailbox, x.host]]
    elsif x.respond_to?(:address)
      [x.name.decoded, x.address]
    elsif x.is_a?(String) || x.is_a?(::Mail::Field)
      begin
        if x.is_a?(::Mail::Field)
          # puts "Converting Mail::Field: #{x.inspect}"
        else
          raise "Processing raw string: #{x}"
        end
        x = x.to_s 
      rescue # may be unknown encoding
        puts "Unknown encoding for email address"
        puts $!
        # just fail
        return
      end
      if x =~ /,/
        puts "Address string contains comma. Splitting: #{x.to_s}"
        x.scan(/\S+@[^\s,]+/).each {|z| parse_email_address(z, f, mail)}
      end
      if x.nil?
        puts "No email address parsed for #{x.inspect}"
        return
      end

      if x[/<([^>\s]+)>/, 1]   # email address and name
        email = x[/<([^>\s]+)>/, 1]
        name = x[/^([^<]+)\s*</, 1]
        [name, email]
      else
        [nil, x]
      end
    else 
      puts "Don't know what to do with #{x.inspect} #{x.class}"
    end
    n, e = *res
    e = e.to_s
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
      n = n ? n.gsub('"', '').strip : nil
      if (contact = Contact.filter(email: e).first).nil?
        contact = Contact.create(email: e, name: n)
      elsif (n && (contact = Contact.filter(email: e, name: n).first)) || 
        (n.nil? && (contact = Contact.filter(email: e).first)) 
      elsif n && (contact = Contact.filter("email = ? and (name != ? or name is null)", e, n).first)
        old_version = contact.to_s
        if contact.name.nil? || (n.length > contact.name.length)
          contact.update name: n
        else
          # reuse contact
        end
      else
        raise "Save Contact Error"
      end
      p = {contact_id: contact.contact_id,
           mail_id: mail.mail_id,
           connection: f}
      if f == 'from'
        puts "#{$mailbox} => Created mail: #{mail.date.strftime("%m-%d-%Y")} | " + 
          "#{("%-30s" % contact)[0,30]} | #{("%-50s" % mail.subject)[0,50]}"
        mail.update(sender_id: contact.contact_id)
      elsif !DB[:connections].filter(p).first
        DB[:connections].insert p
      end
    rescue Sequel::Error
      puts "ERROR. #{$!}"
      puts "email_address: #{e}"
      puts "email_address class: #{e.class}"
      puts "name: #{n}"
      sleep 3
      # Just skip
    end
  end
end

if __FILE__ == $0
  start_idx = (ARGV[0] || 1).to_i
  GmailArchiver.run start_idx
end

