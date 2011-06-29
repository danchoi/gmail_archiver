require 'gmail_archiver/imap_client'
require 'gmail_archiver/database'
require 'yaml'


class GmailArchiver
  def initalize
  end

  def run
    # THIS FOR TESTING ONLY
    config = YAML::load File.read(File.expand_path('~/.vmailrc'))
    imap = GmailArchiver::ImapClient.new(config)

    imap.with_open do |imap|
      ['INBOX', '[Gmail]/Important'].each do |mailbox|

        label = Label[name: mailbox] || Label.create(name: mailbox) 

        imap.select_mailbox mailbox

        imap.get_messages do |x|

          # TODO get headers first and check if message-id is in db
          # If not, then download the RFC822
          #

          text = x.message
          text = Iconv.conv("UTF-8//IGNORE", 'UTF-8', text)

          params = {message_id: x.message_id,
            date: x.date,
            subject: x.subject, 
            seen: x.flags.include?(:Seen),
            in_reply_to: x.in_reply_to,
            text: text,
            size: x.size }

          sender_params = { email: email_address(x.sender) }

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

            DB[:rfc822].insert mail_id:  mail.mail_id, 
              content: (Iconv.conv("UTF-8//IGNORE", 'UTF-8', x.rfc822))


            %w(to cc).each do |f|
              address_structs = x.mail[f]
              next if address_structs.nil?
              address_structs.each do |address|
                e = email_address(address)
                n = address.name
                if e.nil?
                  raise "Nil email: #{address}"
                end
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

  def email_address(address_struct)
    res = if address_struct.respond_to?(:mailbox)
      "%s@%s" % [address_struct.mailbox, address_struct.host]
    else
      address_struct.address
    end
    if res.nil?
      raise "No email address found for struct: #{address_struct}"
    end
    res
  end

end


if __FILE__ == $0
  GmailArchiver.new.run
end

