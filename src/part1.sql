-- create database retail_analytics;

create table personal_information
(
    customer_id            bigserial primary key not null,
    customer_name          varchar(50) check (customer_name ~ '^[А-ЯЁA-Z][а-яёa-z]+$'),
    customer_surname       varchar(50) check (customer_surname ~ '^[А-ЯЁA-Z][а-яёa-z]+$'),
    customer_primary_email varchar(50) check (customer_primary_email ~
                                              '^[A-Za-z0-9._+%-]+@[A-Za-z0-9.-]+[.][A-Za-z]+$'),
    customer_primary_phone varchar(12) check (customer_primary_phone ~ '^[+][7][0-9]{10}')
);


create table cards
(
    customer_card_id bigserial primary key not null,
    customer_id      int                   not null,
    constraint fk_card_id foreign key (customer_id) references personal_information (customer_id) on delete set null
);


create table transactions
(
    transaction_id       bigserial primary key not null,
    customer_card_id     int                   not null,
    transaction_summ     numeric,
    transaction_datetime timestamp default current_timestamp,
    transaction_store_id int                   not null
);

create table bills
(
    transaction_id bigint not null,
    sku_id         int    not null,
    sku_amount     numeric    not null,
    sku_summ       numeric,
    sku_summ_paid  numeric,
    sku_discount   numeric default 0,
    constraint fk_transaction_id foreign key (transaction_id) references transactions (transaction_id) on delete cascade
);


create table products
(
    sku_id   bigserial primary key not null,
    sku_name varchar(50) check ( sku_name ~ '^[A-ZА-Яa-zа-яё0-9 -\[\]\\\^\$\.\|\?\*\+\(\)]+$'),
    group_id int default null
);


create table store
(
    transaction_store_id bigint,
    sku_id               int                   not null,
    sku_purchace_price   numeric check (sku_purchace_price >= 0),
    sku_retail_price     numeric check (sku_retail_price >= 0),
    constraint fk_transaction_id foreign key (sku_id) references products (sku_id) on delete set null
);


create table sku_groups
(
    group_id   bigserial primary key not null,
    group_name varchar(50) check (group_name ~ '^[A-ZА-Яa-zа-яё0-9 -\[\]\\\^\$\.\|\?\*\+\(\)]+$')
);


create table analysis_date
(
    analysis_information timestamp default current_timestamp
);

alter table bills
    ADD CONSTRAINT fk_bills_sku_id
        FOREIGN KEY (sku_id)
            REFERENCES products (sku_id);

alter table products
    ADD CONSTRAINT fk_bills_sku_id
        FOREIGN KEY (group_id)
            REFERENCES sku_groups (group_id)
            on delete set null;

alter table transactions
    add constraint fk_customer_card_id
        foreign key (customer_card_id)
            references cards (customer_card_id)
            on delete set null;
