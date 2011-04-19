# encoding: UTF-8
require 'timeout'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'
require 'gmail_archiver/fetch_data'

module GmailArchiver
  class ImapClient
    attr_accessor :max_seqno 
    def initialize(config)
      @username, @password = config['username'], config['password']
      @imap_server = config['server'] || 'imap.gmail.com'
      @imap_port = config['port'] || 993
    end

    def log s
      if s.is_a?(Net::IMAP::TaggedResponse)
        $stderr.puts s.data.text
      else
        $stderr.puts s
      end
    end

    def with_open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      log @imap.login(@username, @password)
      list_mailboxes
      yield self
      close
    end

    def close
      log "Closing connection"
      Timeout::timeout(5) do
        @imap.close rescue Net::IMAP::BadResponseError
        @imap.disconnect rescue IOError
      end
    rescue Timeout::Error
      log "Attempt to close connection timed out"
    end

    def select_mailbox(mailbox)
      log "Selecting mailbox #{mailbox.inspect}"
      log @imap.select(mailbox)
      @mailbox = mailbox
      return "OK"
    end

    def list_mailboxes
      log 'loading mailboxes...'
      @mailboxes = (@imap.list("", "*") || []).select {|struct| struct.attr.none? {|a| a == :Noselect}}. map {|struct| struct.name}.uniq
      log "Loaded mailboxes: #{@mailboxes.inspect}"
    end

    def archive_messages(per_slice = 100)
      uids = @imap.uid_search('ALL')
      log "Got UIDs for #{uids.size} messages" 
      uids.each_slice(per_slice) do |uid_set|
        @imap.uid_fetch(uid_set, ["FLAGS", 'ENVELOPE', "RFC822", "RFC822.SIZE", 'UID']).each do |x|
          f = FetchData.new x
          puts f.envelope.subject
          sleep 1
        
        end
      end
    end

  end
end

if __FILE__ == $0
  config = YAML::load File.read(File.expand_path('~/.vmailrc'))
  imap = GmailArchiver::ImapClient.new(config)
  imap.with_open do |imap|
    imap.select_mailbox "INBOX"
    imap.archive_messages
  end

end
