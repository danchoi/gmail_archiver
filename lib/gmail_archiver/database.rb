require 'sequel'

DB = Sequel.connect 'postgres:///gmail'

class GmailArchiver
  class Mail < Sequel::Model(:mail)
    set_primary_key :mail_id
  end

  class Contact < Sequel::Model(:contacts)
  end

  class Role < Sequel::Model(:roles)
  end

  class Label < Sequel::Model(:labels)
    set_primary_key :label_id
    one_to_many :labelings
    many_to_many :messages, :join_table => 'labelings'
  end

  class Labeling < Sequel::Model(:labelings)
  end
end


