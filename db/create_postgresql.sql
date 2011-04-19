
-- create postgres db --
drop table if exists contacts_mail;
drop table if exists contacts;
drop table if exists mail;

create table mail (
  mail_id SERIAL,
  uid int UNIQUE,
  sender_id int, 
  subject varchar,
  text text,
  rfc822 text,
  CONSTRAINT mail_pk PRIMARY KEY(mail_id),
  CONSTRAINT mail_sender_id_fk FOREIGN KEY(sender_id) references contacts(contact_id)
);

create table contacts (
  contact_id SERIAL,
  email_address varchar UNIQUE,
  name varchar,
  CONSTRAINT contacts_pk PRIMARY KEY(contact_id)
);

create table contacts_mail (
  contact_id int,
  mail_id int,
  CONSTRAINT contacts_mail_contact_id_fk FOREIGN KEY(contact_id) references contacts(contact_id),
  CONSTRAINT contacts_mail_mail_id_fk FOREIGN KEY(mail_id) references mail(mail_id)
);
