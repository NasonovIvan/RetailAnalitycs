CREATE ROLE Administrator;
CREATE ROLE Visitor;

GRANT ALL PRIVILEGES ON *.* TO Administrator;

GRANT SELECT ON *.* TO Visitor;