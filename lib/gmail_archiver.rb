require 'gmail_archiver/imap_client'
require 'gmail_archiver/database'
require 'yaml'

if __FILE__ == $0
  # THIS FOR TESTING ONLY
  config = YAML::load File.read(File.expand_path('~/.vmailrc'))
  imap = GmailArchiver::ImapClient.new(config)

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

        begin
          m = GmailArchiver::Mail.create params
        rescue
          puts params.inspect
          raise
        end
        puts "created #{m}"
      end
    end
  end

end

