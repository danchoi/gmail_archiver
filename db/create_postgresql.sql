-- create postgres db --
drop table if exists contacts_mail;
drop table if exists contacts cascade;
drop table if exists labels cascade;
drop table if exists mail cascade;

create table contacts (
  contact_id SERIAL,
  email_address varchar UNIQUE,
  name varchar,
  CONSTRAINT contacts_pk PRIMARY KEY(contact_id)
);

create table mail (
  mail_id SERIAL,
  message_id varchar NOT NULL,
  date timestamp with time zone, 
  sender_id int, 
  in_reply_to varchar,
  subject varchar,
  text text,
  rfc822 text,
  CONSTRAINT mail_pk PRIMARY KEY(mail_id),
  CONSTRAINT mail_message_id UNIQUE(message_id),
  CONSTRAINT mail_sender_id_fk FOREIGN KEY(sender_id) REFERENCES contacts(contact_id)
);

-- todo index mailbox, message_id ? --
create table labels (
  mail_id int,
  mailbox varchar,
  CONSTRAINT labels_mail_id_mailbox UNIQUE(mail_id, mailbox),
  CONSTRAINT labels_mail_id_fk FOREIGN KEY(mail_id) REFERENCES mail(mail_id) ON DELETE CASCADE
);

create table contacts_mail (
  contact_id int,
  mail_id int,
  CONSTRAINT contacts_mail_contact_id_fk FOREIGN KEY(contact_id) references contacts(contact_id),
  CONSTRAINT contacts_mail_mail_id_fk FOREIGN KEY(mail_id) references mail(mail_id)
);
