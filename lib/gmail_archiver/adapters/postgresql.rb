require 'pg'
module GmailArchiver
  module Adapters
    class Postgresql
      attr_accessor :conn
      def initialize(config)
        # config is db config, ~/.pgpass can be used
        config = 'dbname=gmail'
        @conn = PGconn.connect config
        conn.exec("delete from contacts") 
        conn.exec("delete from mail") 
      end

      def archive(fd)
        insert_mail(fd)
      end

      def insert_mail(fd)
        sender_id = insert_contact(fd.sender)['contact_id']
        cmd = "insert into mail (uid, sender_id, subject, text, rfc822) values ($1, $2, $3, $4, $5)"
        values = [fd.uid, sender_id, fd.subject, fd.message, fd.rfc822]
        $stderr.puts conn.exec(cmd, values)
      end

      def insert_contact(addr)
        cmd = "insert into contacts (email_address, name) values ($1, $2) returning contact_id"
        values = [[addr.mailbox, addr.host].join('@'), addr.name]
        res = conn.exec(cmd, values)[0]
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


