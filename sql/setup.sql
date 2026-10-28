-- Project Kashi compatibility setup for the existing project_kashi database.
-- Run this file in MySQL Workbench AFTER selecting project_kashi.
-- It does not drop or rebuild existing tables and preserves existing records.
USE project_kashi;

-- The current CUSTOMER.CustomerID and BRANCH.BranchID are signed INT,
-- so the new foreign keys below intentionally use signed INT too.
CREATE TABLE IF NOT EXISTS LOAN (
    LoanID INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    CustomerID INT NOT NULL,
    BranchID INT NOT NULL,
    LoanType ENUM('Home Loan','Education Loan','Personal Loan','Vehicle Loan') NOT NULL,
    LoanAmount DECIMAL(14,2) NOT NULL,
    InterestRate DECIMAL(5,2) NOT NULL,
    StartDate DATE NOT NULL,
    TenureMonths SMALLINT UNSIGNED NOT NULL,
    LoanStatus ENUM('Active','Closed','Rejected') NOT NULL DEFAULT 'Active',
    KEY idx_loan_customer (CustomerID),
    KEY idx_loan_branch (BranchID),
    CONSTRAINT fk_loan_customer_compat FOREIGN KEY (CustomerID) REFERENCES CUSTOMER(CustomerID),
    CONSTRAINT fk_loan_branch_compat FOREIGN KEY (BranchID) REFERENCES BRANCH(BranchID)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS LOAN_PAYMENT (
    PaymentID BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    LoanID INT NOT NULL,
    PaymentDate DATE NOT NULL,
    Amount DECIMAL(14,2) NOT NULL,
    PaymentMode ENUM('Cash','UPI','Bank Transfer','Cheque','Other') NOT NULL,
    ReferenceNumber VARCHAR(40) NULL,
    KEY idx_loan_payment_date (LoanID, PaymentDate),
    CONSTRAINT fk_payment_loan_compat FOREIGN KEY (LoanID) REFERENCES LOAN(LoanID)
) ENGINE=InnoDB;

-- These procedures match the existing signed INT IDs and transaction table.
DROP PROCEDURE IF EXISTS sp_deposit;
DROP PROCEDURE IF EXISTS sp_withdraw;
DROP PROCEDURE IF EXISTS sp_transfer;
DELIMITER $$
CREATE PROCEDURE sp_deposit(IN p_account_id INT, IN p_amount DECIMAL(14,2), IN p_description VARCHAR(255))
BEGIN
    DECLARE v_balance DECIMAL(14,2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_new_balance DECIMAL(14,2);
    DECLARE v_ref VARCHAR(40);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Deposit amount must be positive'; END IF;
    START TRANSACTION;
    SELECT Balance, Status INTO v_balance, v_status FROM ACCOUNT WHERE AccountID=p_account_id FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Account does not exist'; END IF;
    IF v_status <> 'Active' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Account is not active'; END IF;
    SET v_new_balance = v_balance + p_amount;
    IF v_new_balance > 999999999999.99 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Account balance limit exceeded'; END IF;
    SET v_ref = CONCAT('DEP-', REPLACE(UUID(),'-',''));
    UPDATE ACCOUNT SET Balance=v_new_balance WHERE AccountID=p_account_id;
    INSERT INTO `TRANSACTION` (AccountID,TransactionType,Amount,BalanceAfter,Description,ReferenceNumber,TransactionStatus)
    VALUES (p_account_id,'DEPOSIT',p_amount,v_new_balance,p_description,v_ref,'SUCCESS');
    COMMIT;
END$$
CREATE PROCEDURE sp_withdraw(IN p_account_id INT, IN p_amount DECIMAL(14,2), IN p_description VARCHAR(255))
BEGIN
    DECLARE v_balance DECIMAL(14,2);
    DECLARE v_status VARCHAR(20);
    DECLARE v_new_balance DECIMAL(14,2);
    DECLARE v_ref VARCHAR(40);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Withdrawal amount must be positive'; END IF;
    START TRANSACTION;
    SELECT Balance, Status INTO v_balance, v_status FROM ACCOUNT WHERE AccountID=p_account_id FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Account does not exist'; END IF;
    IF v_status <> 'Active' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Account is not active'; END IF;
    IF v_balance < p_amount THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient account balance'; END IF;
    SET v_new_balance = v_balance - p_amount;
    SET v_ref = CONCAT('WDR-', REPLACE(UUID(),'-',''));
    UPDATE ACCOUNT SET Balance=v_new_balance WHERE AccountID=p_account_id;
    INSERT INTO `TRANSACTION` (AccountID,TransactionType,Amount,BalanceAfter,Description,ReferenceNumber,TransactionStatus)
    VALUES (p_account_id,'WITHDRAWAL',p_amount,v_new_balance,p_description,v_ref,'SUCCESS');
    COMMIT;
END$$
CREATE PROCEDURE sp_transfer(IN p_source_id INT, IN p_destination_id INT, IN p_amount DECIMAL(14,2), IN p_description VARCHAR(255))
BEGIN
    DECLARE v_source_balance DECIMAL(14,2);
    DECLARE v_source_status VARCHAR(20);
    DECLARE v_dest_balance DECIMAL(14,2);
    DECLARE v_dest_status VARCHAR(20);
    DECLARE v_ref VARCHAR(40);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount <= 0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Transfer amount must be positive'; END IF;
    IF p_source_id = p_destination_id THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Source and destination must differ'; END IF;
    START TRANSACTION;
    IF p_source_id < p_destination_id THEN
        SELECT Balance,Status INTO v_source_balance,v_source_status FROM ACCOUNT WHERE AccountID=p_source_id FOR UPDATE;
        SELECT Balance,Status INTO v_dest_balance,v_dest_status FROM ACCOUNT WHERE AccountID=p_destination_id FOR UPDATE;
    ELSE
        SELECT Balance,Status INTO v_dest_balance,v_dest_status FROM ACCOUNT WHERE AccountID=p_destination_id FOR UPDATE;
        SELECT Balance,Status INTO v_source_balance,v_source_status FROM ACCOUNT WHERE AccountID=p_source_id FOR UPDATE;
    END IF;
    IF v_source_status IS NULL OR v_dest_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='One or both accounts do not exist'; END IF;
    IF v_source_status <> 'Active' OR v_dest_status <> 'Active' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Both accounts must be active'; END IF;
    IF v_source_balance < p_amount THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Insufficient account balance'; END IF;
    IF v_dest_balance + p_amount > 999999999999.99 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Destination balance limit exceeded'; END IF;
    SET v_ref = CONCAT('TRF-', REPLACE(UUID(),'-',''));
    UPDATE ACCOUNT SET Balance=Balance-p_amount WHERE AccountID=p_source_id;
    UPDATE ACCOUNT SET Balance=Balance+p_amount WHERE AccountID=p_destination_id;
    INSERT INTO `TRANSACTION` (AccountID,TransactionType,Amount,BalanceAfter,Description,ReferenceNumber,TransactionStatus)
    VALUES (p_source_id,'TRANSFER_OUT',p_amount,v_source_balance-p_amount,p_description,CONCAT(v_ref,'-O'),'SUCCESS');
    INSERT INTO `TRANSACTION` (AccountID,TransactionType,Amount,BalanceAfter,Description,ReferenceNumber,TransactionStatus)
    VALUES (p_destination_id,'TRANSFER_IN',p_amount,v_dest_balance+p_amount,p_description,CONCAT(v_ref,'-I'),'SUCCESS');
    COMMIT;
END$$
DELIMITER ;

-- This trigger already exists in the user's database and is intentionally left alone.
