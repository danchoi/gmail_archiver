require 'gmail_archiver/imap_client'
require 'gmail_archiver/database'
require 'yaml'

def email_address(address_struct)
  "%s@%s" % [address_struct.mailbox, address_struct.host]
end

if __FILE__ == $0
  # THIS FOR TESTING ONLY
  config = YAML::load File.read(File.expand_path('~/.vmailrc'))
  imap = GmailArchiver::ImapClient.new(config)

  DB.run("delete from mail")
  imap.with_open do |imap|
    ['INBOX', '[Gmail]/Important'].each do |mailbox|
      imap.select_mailbox mailbox
      imap.get_messages do |x|

        text = x.message
        text = Iconv.conv("UTF-8//IGNORE", 'UTF-8', text)

        params = {message_id: x.message_id,
          date: x.date,
          subject: x.envelope.subject, 
          seen: x.flags.include?(:Seen),
          in_reply_to: x.in_reply_to,
          text: text,
          size: x.size }

        contact_params = {
          email_address: email_address(x.sender)
        }
        begin
          if !(sender = GmailArchiver::Contact[email_address: email_address(x.sender)])
            sender = GmailArchiver::Contact.create contact_params
          end
          mail = GmailArchiver::Mail.create params.merge(sender_id: sender.contact_id)

        rescue
          puts params.inspect
          puts contact_params.inspect
          raise
        end
        puts "created #{mail}"
        puts "created #{sender}"
      end
    end
  end

end

