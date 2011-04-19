require 'pg'
require 'time'
require 'gmail_archiver/adapters/postgresql/mail'

module GmailArchiver
  module Adapters
    class Postgresql
      attr_accessor :conn
      def initialize(config)
        # config is db config, ~/.pgpass can be used
        config = 'dbname=gmail'
        @conn = PGconn.connect config
      end

      def archive(fd, mailbox)
        puts "MESSAGE ID: #{fd.message_id}"
        insert_mail(fd, mailbox)
      end

      def insert_mail(fd, mailbox)
        m_id = mail_id(fd)
        unless labeled?(m_id, mailbox)
          cmd = "insert into labels_mail (mail_id, label_id) values ($1, $2)"
          conn.exec(cmd, [m_id, label_id(mailbox)])
        end
      rescue
        puts "Error executing: #{cmd}"
        raise
      end

      # will create if necessary
      def mail_id(fd)
        cmd = "select mail_id from mail where mail.message_id = $1"
        res = conn.exec(cmd, [fd.message_id])
        if res.ntuples > 0
          res[0]['mail_id']   
        else
          sender_id = contact_id(fd.sender) 
          date = Time.parse(fd.envelope.date).localtime
          cmd = "insert into mail " + 
            "(message_id, date, sender_id, in_reply_to, subject, text, size, rfc822) " + 
            "values ($1, $2, $3, $4, $5, $6, $7, $8) returning mail_id"
          values = [fd.message_id, date, sender_id, fd.in_reply_to, fd.subject, fd.message, fd.size, fd.rfc822]
          conn.exec(cmd, values)[0]['mail_id']
        end
 
      end

      def labeled?(mail_id, mailbox)
        cmd = "select * from labels inner join labels_mail using(label_id) " + 
          "where labels_mail.mail_id = $1 and labels.name = $2"
        res = conn.exec(cmd, [mail_id, mailbox])
        res.ntuples > 0 
      end

      # will create if necessary
      def label_id(name)
        cmd = "select label_id from labels where labels.name = $1"
        res = conn.exec(cmd, [name])
        if res.ntuples > 0 
          res[0]['label_id']
        else
          cmd = "insert into labels (name) values ($1) returning label_id"
          conn.exec(cmd, [name])[0]['label_id']
        end
      end

      # will create if necessary
      def contact_id(addr)
        res = conn.exec("select contact_id from contacts where email_address = $1", [email(addr)])
        if res.ntuples == 0 
          cmd = "insert into contacts (email_address, name) values ($1, $2) returning contact_id"
          values = [email(addr), addr.name]
          conn.exec(cmd, values)[0]['contact_id']
        else
          res[0]['contact_id']
        end
      end

      def find_contact(addr)
      end

      def email(addr)
        [addr.mailbox, addr.host].join('@')
      end

      def self.create_datastore
        # load create_postgresql.sql
      end
    end
  end
end
__END__

require 'event_feeder/sql'

class PgTest < MiniTest::Unit::TestCase

  def test_connection
    config = "host=localhost port=5432 dbname= password="
    e = EventFeeder::Sql.new config
    puts e.inspect
    r = e.venues
    puts r.inspect
    puts r.count # number of results
    # TODO insert this data from fixture
    # PGresult
    r.each do |x|
      puts x.inspect
    end
    expected = {"venue_id"=>"1", "name"=>"Brattle", "url"=>"http://brattlefilm.org/category/calendar-2/special-events/"}
    assert_equal expected, r[0]
    # test params

    r = e.conn.exec("select * from venues where venue_id = $1", [1])
    puts "Prepared stmt res %s" % r[0].inspect

    # string variable
    #r = e.conn.exec("select * from venues where name = $1::varchar", ['Brattle'])
    r = e.conn.exec("select * from venues where name = $1", ['Brattle'])
    puts "Prepared stmt 2 res %s" % r[0].inspect
  end

end


