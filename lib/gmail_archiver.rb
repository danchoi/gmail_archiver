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

    DB.run("delete from mail cascade")

    imap.with_open do |imap|
      ['INBOX', '[Gmail]/Important'].each do |mailbox|
        imap.select_mailbox mailbox
        imap.get_messages do |x|

          text = x.message
          text = Iconv.conv("UTF-8//IGNORE", 'UTF-8', text)

          params = {message_id: x.message_id,
            date: x.date,
            subject: x.subject, 
            seen: x.flags.include?(:Seen),
            in_reply_to: x.in_reply_to,
            text: text,
            size: x.size }

          sender_params = {
            email_address: email_address(x.sender)
          }
          begin

            if !(sender = Contact[email: sender_params[:email]])
              sender = Contact.create(email: sender_params[:email])
            end

            mail = GmailArchiver::Mail.create params.merge(sender_id: sender.contact_id)

            %w(to cc).each do |f|
              address_structs = x.mail[f]
              next if address_structs.nil?
              address_structs.each do |address|
                e = email_address(address)
                n = address.name
                if !(contact = Contact[email: e, name: n])
                  puts "Creating contact: #{e}"
                  contact = Contact.create(email: e, name: n)
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
          puts "created #{mail}"
          puts "created #{sender}"
        end
      end
    end
  end

  def email_address(address_struct)
    if address_struct.respond_to?(:mailbox)
      "%s@%s" % [address_struct.mailbox, address_struct.host]
    else
      address_struct.address
    end
  end

end


if __FILE__ == $0
  GmailArchiver.new.run
end

