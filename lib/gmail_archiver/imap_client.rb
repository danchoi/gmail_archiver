# encoding: UTF-8
require 'timeout'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'
require 'gmail_archiver/fetch_data'

class GmailArchiver
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
    ensure
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
      log @imap.select(mailbox)
      @mailbox = mailbox
    end

    # TODO skip drafts and spam box and all box 
    def list_mailboxes
      log 'loading mailboxes...'
      @mailboxes = (@imap.list("", "*") || []).select {|struct| struct.attr.none? {|a| a == :Noselect}}. map {|struct| struct.name}.uniq
      log "Loaded mailboxes: #{@mailboxes.inspect}"
    end

    def get_messages
      res = @imap.fetch([1,"*"], ["ENVELOPE"])
      max_seqno = res ? res[-1].seqno : 1
      log "Max seqno: #{max_seqno}"
      range = (1..max_seqno)
      range.to_a.each_slice(30) do |id_set|
        @imap.fetch(id_set, ["FLAGS", 'ENVELOPE', 'RFC822', 'RFC822.SIZE']).each do |x|
          yield FetchData.new(x)
        end
      end
    end
  end
end
