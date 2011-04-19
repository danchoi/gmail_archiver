# encoding: UTF-8
require 'timeout'
require 'yaml'
require 'mail'
require 'net/imap'
require 'time'

module GmailArchiver
  class ImapClient
    include Vmail::AddressQuoter

    attr_accessor :max_seqno 

    def initialize(config)
      @username, @password = config['username'], config['password']
      @imap_server = config['server'] || 'imap.gmail.com'
      @imap_port = config['port'] || 993
    end

    def log s
      $stderr.puts s
    end

    def open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      log @imap.login(@username, @password)
    end

    def with_open
      @imap = Net::IMAP.new(@imap_server, @imap_port, true, nil, false)
      log @imap.login(@username, @password)
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

    def select_mailbox(mailbox, force=false)
      log "Selecting mailbox #{mailbox.inspect}"
      log @imap.select(mailbox)
      log "Selected"
      @mailbox = mailbox
      log "Getting mailbox status"
      get_mailbox_status
      log "Getting highest message id"
      get_highest_message_id
      return "OK"
    end

    def get_highest_message_id
      # get highest message ID
      res = @imap.fetch([1,"*"], ["ENVELOPE"])
      if res 
        @num_messages = res[-1].seqno
        log "HIGHEST ID: #@num_messages"
      else
        @num_messages = 1
        log "NO HIGHEST ID: setting @num_messages to 1"
      end
    end

    def list_mailboxes
      log 'loading mailboxes...'
      @mailboxes ||= (@imap.list("", "*") || []).
        select {|struct| struct.attr.none? {|a| a == :Noselect} }.
        map {|struct| struct.name}.uniq
      @mailboxes.delete("INBOX")
      @mailboxes.unshift("INBOX")
      log "Loaded mailboxes: #{@mailboxes.inspect}"
      @mailboxes = @mailboxes.map {|name| mailbox_aliases.invert[name] || name}
      @mailboxes.join("\n")
    end

    # id_set may be a range, array, or string
    def fetch_row_text(id_set, are_uids=false, is_update=false)
      log "Fetch_row_text: #{id_set.inspect}"
      if id_set.is_a?(String)
        id_set = id_set.split(',')
      end
      if id_set.to_a.empty?
        log "- empty set"
        return ""
      end
      new_message_rows = fetch_envelopes(id_set, are_uids, is_update)
      new_message_rows.map {|x| x[:row_text]}.join("\n")
    rescue # Encoding::CompatibilityError (only in 1.9.2)
      log "Error in fetch_row_text:\n#{$!}\n#{$!.backtrace}"
      new_message_rows.map {|x| Iconv.conv('US-ASCII//TRANSLIT//IGNORE', 'UTF-8', x[:row_text])}.join("\n")
    end

    def fetch_envelopes(id_set, are_uids, is_update)
      results = reconnect_if_necessary do 
        if are_uids
          @imap.uid_fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID" ])
        else
          @imap.fetch(id_set, ["FLAGS", "ENVELOPE", "RFC822.SIZE", "UID" ])
        end
      end
      if results.nil?
        error = "Expected fetch results but got nil"
        log(error) && raise(error)
      end
      log "- extracting headers"
      new_message_rows = results.map {|x| extract_row_data(x) }
      log "- returning #{new_message_rows.size} new rows and caching result"  
      new_message_rows
    end

    # TODO extract this to another class or module and write unit tests
    def extract_row_data(fetch_data)
      seqno = fetch_data.seqno
      uid = fetch_data.attr['UID']
      # log "fetched seqno #{seqno} uid #{uid}"
      envelope = fetch_data.attr["ENVELOPE"]
      size = fetch_data.attr["RFC822.SIZE"]
      flags = fetch_data.attr["FLAGS"]
      address_struct = if @mailbox == mailbox_aliases['sent'] 
                         structs = envelope.to || envelope.cc
                         structs.nil? ? nil : structs.first 
                       else
                         envelope.from.first
                       end
      address = if address_struct.nil?
                  "Unknown"
                elsif address_struct.name
                  "#{Mail::Encodings.unquote_and_convert_to(address_struct.name, 'UTF-8')} <#{[address_struct.mailbox, address_struct.host].join('@')}>"
                else
                  [Mail::Encodings.unquote_and_convert_to(address_struct.mailbox, 'UTF-8'), Mail::Encodings.unquote_and_convert_to(address_struct.host, 'UTF-8')].join('@') 
                end
      if @mailbox == mailbox_aliases['sent'] && envelope.to && envelope.cc
        total_recips = (envelope.to + envelope.cc).size
        address += " + #{total_recips - 1}"
      end
      date = begin 
               Time.parse(envelope.date).localtime
             rescue ArgumentError
               Time.now
             end

      date_formatted = if date.year != Time.now.year
                         date.strftime "%b %d %Y" rescue envelope.date.to_s 
                       else 
                         date.strftime "%b %d %I:%M%P" rescue envelope.date.to_s 
                       end
      subject = envelope.subject || ''
      subject = Mail::Encodings.unquote_and_convert_to(subject, 'UTF-8')
      flags = format_flags(flags)
      mid_width = @width - 38
      address_col_width = (mid_width * 0.3).ceil
      subject_col_width = (mid_width * 0.7).floor
      identifier = [seqno.to_i, uid.to_i].join(':')
      row_text = [ flags.col(2),
                   (date_formatted || '').col(14),
                   address.col(address_col_width),
                   subject.col(subject_col_width), 
                   number_to_human_size(size).rcol(7), 
                   identifier.to_s
      ].join(' | ')
      {:uid => uid, :seqno => seqno, :row_text => row_text}
    rescue 
      log "Error extracting header for uid #{uid} seqno #{seqno}: #$!\n#{$!.backtrace}"
      row_text = "#{seqno.to_s} : error extracting this header"
      {:uid => uid, :seqno => seqno, :row_text => row_text}
    end

    UNITS = [:b, :kb, :mb, :gb].freeze

    # borrowed from ActionView/Helpers
    def number_to_human_size(number)
      if number.to_i < 1024
        "<1kb" # round up to 1kh
      else
        max_exp = UNITS.size - 1
        exponent = (Math.log(number) / Math.log(1024)).to_i # Convert to base 1024
        exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
        number  /= 1024 ** exponent
        unit = UNITS[exponent]
        "#{number}#{unit}"
      end
    end

    def search(query)
      query = Vmail::Query.parse(query)
      @limit = query.shift.to_i
      # a limit of zero is effectively no limit
      if @limit == 0
        @limit = @num_messages
      end
      if query.size == 1 && query[0].downcase == 'all'
        # form a sequence range
        query.unshift [[@num_messages - @limit + 1 , 1].max, @num_messages].join(':')
        @all_search = true
      else # this is a special query search
        # set the target range to the whole set
        query.unshift "1:#@num_messages"
        @all_search = false
      end
      @query = query.map {|x| x.to_s.downcase}
      query_string = Vmail::Query.args2string(@query)
      log "Search query: #{@query} > #{query_string.inspect}"
      log "- @all_search #{@all_search}"
      @query = query
      @ids = reconnect_if_necessary(180) do # increase timeout to 3 minutes
        @imap.search(query_string)
      end
      # save ids in @ids, because filtered search relies on it
      fetch_ids = if @all_search
                    @ids
                  else #filtered search
                    @start_index = [@ids.length - @limit, 0].max
                    @ids[@start_index..-1]
                  end
      self.max_seqno = @ids[-1]
      log "- search query got #{@ids.size} results; max seqno: #{self.max_seqno}" 
      clear_cached_message
      res = fetch_row_text(fetch_ids)
      if STDOUT.tty?
        add_more_message_line(res, fetch_ids[0])
      else
        # non interactive mode
        puts [@mailbox, res].join("\n")
      end
    rescue
      log "ERROR:\n#{$!.inspect}\n#{$!.backtrace.join("\n")}"
    end

    def show_message(uid, raw=false)
      log "Show message: #{uid}"
      return @current_mail.to_s if raw 
      uid = uid.to_i
      if uid == @current_message_uid 
        return @current_message 
      end
      # TODO keep state in vim buffers, instead of on Vmail Ruby client
      # envelope_data[:row_text] = envelope_data[:row_text].gsub(/^\+ /, '  ').gsub(/^\*\+/, '* ') # mark as read in cache
      #seqno = envelope_data[:seqno]

      log "Showing message uid: #{uid}"
      data = if x = message_cache[[@mailbox, uid]]
               log "- message cache hit"
               x
             else 
               log "- fetching and storing to message_cache[[#{@mailbox}, #{uid}]]"
               fetch_and_cache(uid)
             end
      if data.nil?
        # retry, though this is a hack!
        log "- data is nil. retrying..."
        return show_message(uid, raw)
      end
      # make this more DRY later by directly using a ref to the hash
      mail = data[:mail]
      size = data[:size] 
      @current_message_uid = uid
      log "- setting @current_mail"
      @current_mail = mail # used later to show raw message or extract attachments if any
      @current_message = data[:message_text]
    rescue
      log "Parsing error"
      "Error encountered parsing this message:\n#{$!}\n#{$!.backtrace.join("\n")}"
    end

    def fetch_and_cache(uid)
      if data = message_cache[[@mailbox, uid]] 
        return data
      end
      fetch_data = reconnect_if_necessary do 
        res = @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        if res.nil?
          # retry one more time ( find a more elegant way to do this )
          res = @imap.uid_fetch(uid, ["FLAGS", "RFC822", "RFC822.SIZE"])
        end
        res[0] 
      end
      # USE THIS
      size = fetch_data.attr["RFC822.SIZE"]
      flags = fetch_data.attr["FLAGS"]
      mail = Mail.new(fetch_data.attr['RFC822'])
      formatter = Vmail::MessageFormatter.new(mail)
      message_text = <<-EOF
#{@mailbox} uid:#{uid} #{number_to_human_size size} #{flags.inspect} #{format_parts_info(formatter.list_parts)}
#{divider '-'}
#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
      # log "Storing message_cache[[#{@mailbox}, #{uid}]]"
      d = {:mail => mail, :size => size, :message_text => message_text, :seqno => fetch_data.seqno, :flags => flags}
      message_cache[[@mailbox, uid]] = d
    rescue
      msg = "Error encountered parsing message uid  #{uid}:\n#{$!}\n#{$!.backtrace.join("\n")}" + 
        "\n\nRaw message:\n\n" + mail.to_s
      log msg
      log message_text
      {:message_text => msg}
    end

    def format_parts_info(parts)
      lines = parts.select {|part| part !~ %r{text/plain}}
      if lines.size > 0
        "\n#{lines.join("\n")}"
      end
    end

    # id_set is a string comming from the vim client
    # action is -FLAGS or +FLAGS
    def flag(uid_set, action, flg)
      log "Flag #{uid_set} #{flg} #{action}"
      uid_set = uid_set.split(',').map(&:to_i)
      if flg == 'Deleted'
        log "Deleting uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        # for delete, do in a separate thread because deletions are slow
        spawn_thread_if_tty do 
          unless @mailbox == mailbox_aliases['trash']
            log "@imap.uid_copy #{uid_set.inspect} to #{mailbox_aliases['trash']}"
            log @imap.uid_copy(uid_set, mailbox_aliases['trash'])
          end
          log "@imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
          reload_mailbox
          clear_cached_message
        end
      elsif flg == 'spam' || flg == mailbox_aliases['spam'] 
        log "Marking as spam uid_set: #{uid_set.inspect}"
        decrement_max_seqno(uid_set.size)
        spawn_thread_if_tty do 
          log "@imap.uid_copy #{uid_set.inspect} to #{mailbox_aliases['spam']}"
          log @imap.uid_copy(uid_set, mailbox_aliases['spam']) 
          log "@imap.uid_store #{uid_set.inspect} #{action} [:Deleted]"
          log @imap.uid_store(uid_set, action, [:Deleted])
          reload_mailbox
          clear_cached_message
        end
      else
        log "Flagging uid_set: #{uid_set.inspect}"
        spawn_thread_if_tty do
          log "@imap.uid_store #{uid_set.inspect} #{action} [#{flg.to_sym}]"
          log @imap.uid_store(uid_set, action, [flg.to_sym])
        end
      end
    end

    def new_message_template(subject = nil, append_signature = true)
      headers = {'from' => "#{@name} <#{@username}>",
        'to' => nil,
        'subject' => subject,
        'cc' => @always_cc 
      }
      format_headers(headers) + (append_signature ? ("\n\n" + signature) : "\n\n")
    end

    def format_headers(hash)
      lines = []
      hash.each_pair do |key, value|
        if value.is_a?(Array)
          value = value.join(", ")
        end
        lines << "#{key.gsub("_", '-')}: #{value}"
      end
      lines.join("\n")
    end

    def divider(str)
      str * DIVIDER_WIDTH
    end

    SENT_MESSAGES_FILE = "sent-messages.txt"

    def format_sent_message(mail)
      formatter = Vmail::MessageFormatter.new(mail)
      message_text = <<-EOF
Sent Message #{self.format_parts_info(formatter.list_parts)}

#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
    end

    def open_html_part
      log "Open_html_part"
      log @current_mail.parts.inspect
      multipart = @current_mail.parts.detect {|part| part.multipart?}
      html_part = if multipart 
                    multipart.parts.detect {|part| part.header["Content-Type"].to_s =~ /text\/html/}
                  elsif ! @current_mail.parts.empty?
                    @current_mail.parts.detect {|part| part.header["Content-Type"].to_s =~ /text\/html/}
                  else
                    @current_mail.body
                  end
      return if html_part.nil?
      outfile = 'part.html'
      File.open(outfile, 'w') {|f| f.puts(html_part.decoded)}
      # client should handle opening the html file
      return outfile
    end
  end
end

trap("INT") { 
  require 'timeout'
  puts "Closing imap connection"  
  begin
    Timeout::timeout(10) do 
      $gmail.close
    end
  rescue Timeout::Error
    puts "Close connection attempt timed out"
  end
  exit
}


