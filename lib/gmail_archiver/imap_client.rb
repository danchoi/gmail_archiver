# encoding: UTF-8
require 'timeout'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'

class GmailArchiver
  class ImapClient
    attr_accessor :max_seqno, :imap
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
      yield 
    ensure
      # close
    end

    def reopen
      puts "Reopening IMAP connection"
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      @imap.login(@username, @password)
      select_mailbox @mailbox
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
      log @imap.select(mailbox)
      @mailbox = mailbox
    end

    # TODO skip drafts and spam box and all box 
    def list_mailboxes
      log 'loading mailboxes...'
      @mailboxes = (@imap.list("", "*") || []).select {|struct| struct.attr.none? {|a| a == :Noselect}}. map {|struct| struct.name}.uniq
      log "Loaded mailboxes: #{@mailboxes.inspect}"
    end

  end
end
