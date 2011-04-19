require 'mail'
require 'gmail_archiver/message_formatter'
module GmailArchiver
  class FetchData
    attr_accessor :seqno, :uid, :envelope, :rfc822, :size, :flags

    def initialize(x)
      @seq = x.seqno
      @uid = x.attr['UID']
      @message_id = x.attr["MESSAGE-ID"]
      @envelope = x.attr["ENVELOPE"]
      @size = x.attr["RFC822.SIZE"] # not sure what units this is
      @flags = x.attr["FLAGS"]  # e.g. [:Seen]
      @rfc822 = x.attr['RFC822']
      @mail = Mail.new(x.attr['RFC822'])
    end

    def subject
      envelope.subject
    end

    def sender
      envelope.from.first
    end

    def message_id
      envelope.message_id
    end
    # http://www.ruby-doc.org/stdlib/libdoc/net/imap/rdoc/classes/Net/IMAP.html
    #

    def message
      formatter = MessageFormatter.new(@mail)
      message_text = <<-EOF
#{format_headers(formatter.extract_headers)}

#{formatter.process_body}
EOF
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

  end
end

# envelope.from # array
# envelope.to # array
# address_struct.name, mailbox, host , join @
# envelope.date
# envelope.subject
# subject = Mail::Encodings.unquote_and_convert_to((envelope.subject || ''), 'UTF-8')
#
