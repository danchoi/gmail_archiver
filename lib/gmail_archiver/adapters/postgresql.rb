require 'pg'
require 'time'
module GmailArchiver
  module Adapters
    class Postgresql
      attr_accessor :conn
      def initialize(config)
        # config is db config, ~/.pgpass can be used
        config = 'dbname=gmail'
        @conn = PGconn.connect config
        conn.exec("delete from mail") 
        conn.exec("delete from contacts_mail") 
        conn.exec("delete from contacts") 
      end

      def archive(fd, mailbox)
        puts "MESSAGE ID: #{fd.message_id}"
        insert_mail(fd, mailbox)
      end

      # TODO insert label in labels
      def insert_mail(fd, mailbox)
        # TODO check if mail exists already 

        sender_id = find_contact(fd.sender) || insert_contact(fd.sender)
        date = Time.parse(fd.envelope.date).localtime
        cmd = "insert into mail (message_id, date, sender_id, subject, text, rfc822) values ($1, $2, $3, $4, $5, $6)"
        values = [fd.message_id, date, sender_id, fd.subject, fd.message, fd.rfc822]
        $stderr.puts conn.exec(cmd, values)
      rescue
        puts "Error executing: #{cmd}"
        raise
      end

      def insert_contact(addr)
        cmd = "insert into contacts (email_address, name) values ($1, $2) returning contact_id"
        values = [email(addr), addr.name]
        res = conn.exec(cmd, values)[0]['contact_id']
      end

      def find_contact(addr)
        res = conn.exec("select contact_id from contacts where email_address = $1", [email(addr)])
        res.ntuples == 0 ? nil : res[0]['contact_id']
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


