-- create postgres db --
drop table if exists connections;
drop table if exists contacts cascade;
drop table if exists labels cascade;
drop table if exists labelsings cascade;
drop table if exists rfc822 cascade;
drop table if exists mail cascade;

create table contacts (
  contact_id SERIAL,
  name varchar,
  email varchar NOT NULL,
  CONSTRAINT contacts_pk PRIMARY KEY(contact_id),
  UNIQUE (email, name)
);

create table mail (
  mail_id SERIAL,
  message_id varchar NOT NULL,
  date timestamp with time zone, 
  sender_id int, 
  in_reply_to varchar,
  subject varchar,
  text text,
  size int,
  seen boolean,
  rfc822 text,
  CONSTRAINT mail_pk PRIMARY KEY(mail_id),
  CONSTRAINT mail_message_id UNIQUE(message_id),
  CONSTRAINT mail_sender_id_fk FOREIGN KEY(sender_id) REFERENCES contacts(contact_id) ON DELETE CASCADE
);

create table labels (
  label_id SERIAL PRIMARY KEY,
  name varchar,
  CONSTRAINT labels_name UNIQUE(name)
);

create table labelings (
  mail_id int references mail(mail_id) on delete cascade,
  label_id int references labels(label_id) on delete cascade,
  UNIQUE(mail_id, label_id)
);

create type connection as enum ('to', 'cc');

create table connections (
  contact_id int,
  mail_id int,
  connection connection,
  CONSTRAINT connection_contact_id_fk FOREIGN KEY(contact_id) references contacts(contact_id) ON DELETE CASCADE,
  CONSTRAINT connection_mail_id_fk FOREIGN KEY(mail_id) references mail(mail_id) on delete cascade,
  UNIQUE (contact_id, mail_id, connection)
);

