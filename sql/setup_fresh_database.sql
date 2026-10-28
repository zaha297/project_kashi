-- Project Kashi schema and database objects
-- MySQL 8.0+. Run this file once in MySQL Workbench.
-- Safe with respect to existing data: no DROP DATABASE or DROP TABLE statements.
CREATE DATABASE IF NOT EXISTS project_kashi CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE project_kashi;

CREATE TABLE IF NOT EXISTS CUSTOMER (
    CustomerID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    FirstName VARCHAR(60) NOT NULL,
    LastName VARCHAR(60) NOT NULL,
    DateOfBirth DATE NOT NULL,
    Gender ENUM('Female','Male','Other','Prefer not to say') NOT NULL,
    Mobile VARCHAR(20) NOT NULL,
    Email VARCHAR(120) NOT NULL,
    Address VARCHAR(255) NOT NULL,
    City VARCHAR(80) NOT NULL,
    RegistrationDate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_customer_email (Email),
    KEY idx_customer_name (LastName, FirstName)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS BRANCH (
    BranchID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    BranchName VARCHAR(100) NOT NULL,
    IFSCCode CHAR(11) NOT NULL,
    Address VARCHAR(255) NOT NULL,
    City VARCHAR(80) NOT NULL,
    State VARCHAR(80) NOT NULL,
    ContactNumber VARCHAR(20) NOT NULL,
    UNIQUE KEY uq_branch_ifsc (IFSCCode)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS EMPLOYEE (
    EmployeeID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    EmployeeName VARCHAR(120) NOT NULL,
    Mobile VARCHAR(20) NOT NULL,
    Email VARCHAR(120) NOT NULL,
    Designation VARCHAR(80) NOT NULL,
    Salary DECIMAL(12,2) NOT NULL,
    JoiningDate DATE NOT NULL,
    BranchID INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_employee_email (Email),
    CONSTRAINT chk_employee_salary CHECK (Salary >= 0),
    CONSTRAINT fk_employee_branch FOREIGN KEY (BranchID) REFERENCES BRANCH(BranchID)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ACCOUNT (
    AccountID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    AccountNumber VARCHAR(20) NOT NULL,
    AccountType ENUM('Saving','Current','Salary') NOT NULL,
    OpeningDate DATE NOT NULL,
    Balance DECIMAL(15,2) NOT NULL DEFAULT 0.00,
    Status ENUM('Active','Inactive','Close') NOT NULL DEFAULT 'Active',
    BranchID INT UNSIGNED NOT NULL,
    UNIQUE KEY uq_account_number (AccountNumber),
    KEY idx_account_branch (BranchID),
    CONSTRAINT chk_account_balance CHECK (Balance >= 0),
    CONSTRAINT fk_account_branch FOREIGN KEY (BranchID) REFERENCES BRANCH(BranchID)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ACCOUNT_HOLDER (
    CustomerID INT UNSIGNED NOT NULL,
    AccountID INT UNSIGNED NOT NULL,
    HolderSince DATE NOT NULL,
    HolderType VARCHAR(30) NOT NULL DEFAULT 'Primary',
    PRIMARY KEY (CustomerID, AccountID),
    KEY idx_holder_account (AccountID),
    CONSTRAINT fk_holder_customer FOREIGN KEY (CustomerID) REFERENCES CUSTOMER(CustomerID)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_holder_account FOREIGN KEY (AccountID) REFERENCES ACCOUNT(AccountID)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS `TRANSACTION` (
    TransactionID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    AccountID INT UNSIGNED NOT NULL,
    TransactionType ENUM('DEPOSIT','WITHDRAWAL','TRANSFER_IN','TRANSFER_OUT') NOT NULL,
    Amount DECIMAL(15,2) NOT NULL,
    TransactionDate TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Description VARCHAR(255),
    ReferenceNumber VARCHAR(80) NOT NULL,
    TransactionStatus ENUM('SUCCESS','FAILED') NOT NULL DEFAULT 'SUCCESS',
    KEY idx_transaction_account_date (AccountID, TransactionDate),
    UNIQUE KEY uq_transaction_reference (ReferenceNumber),
    CONSTRAINT chk_transaction_amount CHECK (Amount > 0),
    CONSTRAINT fk_transaction_account FOREIGN KEY (AccountID) REFERENCES ACCOUNT(AccountID)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS LOAN (
    LoanID INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT UNSIGNED NOT NULL,
    BranchID INT UNSIGNED NOT NULL,
    LoanType ENUM('Home Loan','Education Loan','Personal Loan','Vehicle Loan') NOT NULL,
    LoanAmount DECIMAL(15,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    StartDate DATE NOT NULL,
    TenureMonths SMALLINT UNSIGNED NOT NULL,
    LoanStatus ENUM('Active','Closed','Rejected') NOT NULL DEFAULT 'Active',
    KEY idx_loan_customer (CustomerID),
    KEY idx_loan_branch (BranchID),
    CONSTRAINT chk_loan_amount CHECK (LoanAmount > 0),
    CONSTRAINT chk_loan_rate CHECK (InterestRate >= 0 AND InterestRate <= 100),
    CONSTRAINT chk_loan_tenure CHECK (TenureMonths > 0),
    CONSTRAINT fk_loan_customer FOREIGN KEY (CustomerID) REFERENCES CUSTOMER(CustomerID)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_loan_branch FOREIGN KEY (BranchID) REFERENCES BRANCH(BranchID)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS LOAN_PAYMENT (
    PaymentID BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    LoanID INT UNSIGNED NOT NULL,
    PaymentDate DATE NOT NULL,
    Amount DECIMAL(15,2) NOT NULL,
    PaymentMode ENUM('Cash','UPI','Bank Transfer','Cheque','Other') NOT NULL,
    ReferenceNumber VARCHAR(80),
    KEY idx_loan_payment_date (LoanID, PaymentDate),
    CONSTRAINT chk_loan_payment_amount CHECK (Amount > 0),
    CONSTRAINT fk_payment_loan FOREIGN KEY (LoanID) REFERENCES LOAN(LoanID)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Re-create programmable objects without deleting application data.
DROP VIEW IF EXISTS v_account_balances;
DROP VIEW IF EXISTS v_loan_payment_summary;
CREATE VIEW v_account_balances AS
SELECT a.AccountID, a.AccountNumber, a.AccountType, a.Balance, a.Status,
       b.BranchName, b.IFSCCode,
       GROUP_CONCAT(CONCAT(c.FirstName, ' ', c.LastName) ORDER BY c.CustomerID SEPARATOR ', ') AS AccountHolders
FROM ACCOUNT a
JOIN BRANCH b ON b.BranchID = a.BranchID
LEFT JOIN ACCOUNT_HOLDER ah ON ah.AccountID = a.AccountID
LEFT JOIN CUSTOMER c ON c.CustomerID = ah.CustomerID
GROUP BY a.AccountID, a.AccountNumber, a.AccountType, a.Balance, a.Status, b.BranchName, b.IFSCCode;

CREATE VIEW v_loan_payment_summary AS
SELECT l.LoanID, l.CustomerID, CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
       l.LoanType, l.LoanAmount, l.InterestRate, l.TenureMonths, l.LoanStatus,
       COALESCE(SUM(lp.Amount), 0.00) AS TotalPaid,
       GREATEST(l.LoanAmount - COALESCE(SUM(lp.Amount), 0.00), 0.00) AS PrincipalBalance
FROM LOAN l JOIN CUSTOMER c ON c.CustomerID = l.CustomerID
LEFT JOIN LOAN_PAYMENT lp ON lp.LoanID = l.LoanID
GROUP BY l.LoanID, l.CustomerID, c.FirstName, c.LastName, l.LoanType, l.LoanAmount,
         l.InterestRate, l.TenureMonths, l.LoanStatus;

DROP FUNCTION IF EXISTS fn_customer_account_count;
DROP FUNCTION IF EXISTS fn_loan_total_paid;
DROP PROCEDURE IF EXISTS sp_deposit;
DROP PROCEDURE IF EXISTS sp_withdraw;
DROP PROCEDURE IF EXISTS sp_transfer;
DROP TRIGGER IF EXISTS trg_transaction_validate;
DROP TRIGGER IF EXISTS trg_transaction_apply_balance;
DROP TRIGGER IF EXISTS trg_transaction_no_update;
DROP TRIGGER IF EXISTS trg_transaction_no_delete;
DROP TRIGGER IF EXISTS trg_loan_payment_validate;

DELIMITER $$
CREATE FUNCTION fn_customer_account_count(p_customer_id INT UNSIGNED)
RETURNS INT UNSIGNED READS SQL DATA
BEGIN
    DECLARE v_count INT UNSIGNED DEFAULT 0;
    SELECT COUNT(*) INTO v_count FROM ACCOUNT_HOLDER WHERE CustomerID = p_customer_id;
    RETURN v_count;
END$$

CREATE FUNCTION fn_loan_total_paid(p_loan_id INT UNSIGNED)
RETURNS DECIMAL(15,2) READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(15,2) DEFAULT 0.00;
    SELECT COALESCE(SUM(Amount), 0.00) INTO v_total FROM LOAN_PAYMENT WHERE LoanID = p_loan_id;
    RETURN v_total;
END$$

CREATE TRIGGER trg_transaction_validate
BEFORE INSERT ON `TRANSACTION`
FOR EACH ROW
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_status VARCHAR(20);
    IF NEW.Amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction amount must be positive';
    END IF;
    SELECT Balance, Status INTO v_balance, v_status FROM ACCOUNT WHERE AccountID = NEW.AccountID;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist';
    END IF;
    IF NEW.TransactionType IN ('WITHDRAWAL','TRANSFER_OUT') AND v_balance < NEW.Amount THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient account balance';
    END IF;
    IF NEW.TransactionType IN ('DEPOSIT','TRANSFER_IN') AND v_balance + NEW.Amount > 9999999999999.99 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account balance limit exceeded';
    END IF;
    IF v_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not active';
    END IF;
    IF NEW.ReferenceNumber IS NULL OR CHAR_LENGTH(TRIM(NEW.ReferenceNumber)) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction reference is required';
    END IF;
END$$

CREATE TRIGGER trg_transaction_apply_balance
AFTER INSERT ON `TRANSACTION`
FOR EACH ROW
BEGIN
    IF NEW.TransactionStatus = 'SUCCESS' THEN
        IF NEW.TransactionType IN ('DEPOSIT','TRANSFER_IN') THEN
            UPDATE ACCOUNT SET Balance = Balance + NEW.Amount WHERE AccountID = NEW.AccountID;
        ELSEIF NEW.TransactionType IN ('WITHDRAWAL','TRANSFER_OUT') THEN
            UPDATE ACCOUNT SET Balance = Balance - NEW.Amount WHERE AccountID = NEW.AccountID;
        END IF;
    END IF;
END$$

CREATE TRIGGER trg_transaction_no_update
BEFORE UPDATE ON `TRANSACTION`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction ledger entries are immutable';
END$$

CREATE TRIGGER trg_transaction_no_delete
BEFORE DELETE ON `TRANSACTION`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transaction ledger entries cannot be deleted';
END$$

CREATE TRIGGER trg_loan_payment_validate
BEFORE INSERT ON LOAN_PAYMENT
FOR EACH ROW
BEGIN
    DECLARE v_status VARCHAR(20);
    SELECT LoanStatus INTO v_status FROM LOAN WHERE LoanID = NEW.LoanID;
    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Loan does not exist';
    END IF;
    IF v_status <> 'Active' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Loan is not active';
    END IF;
    IF NEW.Amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment amount must be positive';
    END IF;
END$$

CREATE PROCEDURE sp_deposit(
    IN p_account_id INT UNSIGNED,
    IN p_amount DECIMAL(15,2),
    IN p_description VARCHAR(255)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_ref VARCHAR(80);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Deposit amount must be positive';
    END IF;
    START TRANSACTION;
    SELECT Balance, Status INTO v_balance, v_status FROM ACCOUNT WHERE AccountID=p_account_id FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist'; END IF;
    IF v_status <> 'Active' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not active'; END IF;
    SET v_ref = CONCAT('DEP-', REPLACE(UUID(), '-', ''));
    INSERT INTO `TRANSACTION` (AccountID, TransactionType, Amount, Description, ReferenceNumber, TransactionStatus)
    VALUES (p_account_id, 'DEPOSIT', p_amount, p_description, v_ref, 'SUCCESS');
    COMMIT;
END$$

CREATE PROCEDURE sp_withdraw(
    IN p_account_id INT UNSIGNED,
    IN p_amount DECIMAL(15,2),
    IN p_description VARCHAR(255)
)
BEGIN
    DECLARE v_balance DECIMAL(15,2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_ref VARCHAR(80);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Withdrawal amount must be positive';
    END IF;
    START TRANSACTION;
    SELECT Balance, Status INTO v_balance, v_status FROM ACCOUNT WHERE AccountID=p_account_id FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account does not exist'; END IF;
    IF v_status <> 'Active' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Account is not active'; END IF;
    IF v_balance < p_amount THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient account balance'; END IF;
    SET v_ref = CONCAT('WDR-', REPLACE(UUID(), '-', ''));
    INSERT INTO `TRANSACTION` (AccountID, TransactionType, Amount, Description, ReferenceNumber, TransactionStatus)
    VALUES (p_account_id, 'WITHDRAWAL', p_amount, p_description, v_ref, 'SUCCESS');
    COMMIT;
END$$

CREATE PROCEDURE sp_transfer(
    IN p_source_id INT UNSIGNED,
    IN p_destination_id INT UNSIGNED,
    IN p_amount DECIMAL(15,2),
    IN p_description VARCHAR(255)
)
BEGIN
    DECLARE v_source_balance DECIMAL(15,2);
    DECLARE v_source_status VARCHAR(20);
    DECLARE v_dest_status VARCHAR(20);
    DECLARE v_dest_balance DECIMAL(15,2);
    DECLARE v_ref VARCHAR(80);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Transfer amount must be positive';
    END IF;
    IF p_source_id = p_destination_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Source and destination must differ';
    END IF;
    START TRANSACTION;
    -- Lock both accounts in a stable ID order to reduce deadlock risk.
    IF p_source_id < p_destination_id THEN
        SELECT Balance, Status INTO v_source_balance, v_source_status FROM ACCOUNT WHERE AccountID=p_source_id FOR UPDATE;
        SELECT Balance, Status INTO v_dest_balance, v_dest_status FROM ACCOUNT WHERE AccountID=p_destination_id FOR UPDATE;
    ELSE
        SELECT Balance, Status INTO v_dest_balance, v_dest_status FROM ACCOUNT WHERE AccountID=p_destination_id FOR UPDATE;
        SELECT Balance, Status INTO v_source_balance, v_source_status FROM ACCOUNT WHERE AccountID=p_source_id FOR UPDATE;
    END IF;
    IF v_source_status IS NULL OR v_dest_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'One or both accounts do not exist'; END IF;
    IF v_source_status <> 'Active' OR v_dest_status <> 'Active' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Both accounts must be active'; END IF;
    IF v_source_balance < p_amount THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient account balance'; END IF;
    SET v_ref = CONCAT('TRF-', REPLACE(UUID(), '-', ''));
    INSERT INTO `TRANSACTION` (AccountID, TransactionType, Amount, Description, ReferenceNumber, TransactionStatus)
    VALUES (p_source_id, 'TRANSFER_OUT', p_amount, p_description, CONCAT(v_ref,'-O'), 'SUCCESS');
    INSERT INTO `TRANSACTION` (AccountID, TransactionType, Amount, Description, ReferenceNumber, TransactionStatus)
    VALUES (p_destination_id, 'TRANSFER_IN', p_amount, p_description, CONCAT(v_ref,'-I'), 'SUCCESS');
    COMMIT;
END$$
DELIMITER ;

-- End of schema and database object setup. No sample data is inserted.
