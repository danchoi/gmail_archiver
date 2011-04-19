require 'mail'
module GmailArchiver
  class FetchData
    attr_accessor :seqno, :uid, :envelope, :size, :flags

    def initialize(x)
      @seq = x.seqno
      @uid = x.attr['UID']
      @envelope = x.attr["ENVELOPE"]
      @size = x.attr["RFC822.SIZE"] # not sure what units this is
      @flags = x.attr["FLAGS"]  # e.g. [:Seen]
      @mail = Mail.new(x.attr['RFC822'])
    end

    def message
            formatter = Vmail::MessageFormatter.new(mail)
            message_text = <<-EOF
#{@mailbox} uid:#{uid} #{number_to_human_size size} #{flags.inspect} #{format_parts_info(formatter.list_parts)}
#{divider '-'}
#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
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


# envelope.from # array
# envelope.to # array
# address_struct.name, mailbox, host , join @
# envelope.date
# envelope.subject
# subject = Mail::Encodings.unquote_and_convert_to((envelope.subject || ''), 'UTF-8')
#
