-- Project Kashi: 10+ meaningful business questions for MySQL Workbench.
USE project_kashi;

-- 1. List each account, branch, current balance, and account holders.
SELECT * FROM v_account_balances ORDER BY BranchName, AccountNumber;

-- 2. Total deposits and withdrawals per account.
SELECT a.AccountNumber,
       SUM(CASE WHEN t.TransactionType IN ('DEPOSIT','TRANSFER_IN') THEN t.Amount ELSE 0 END) AS TotalCredits,
       SUM(CASE WHEN t.TransactionType IN ('WITHDRAWAL','TRANSFER_OUT') THEN t.Amount ELSE 0 END) AS TotalDebits
FROM ACCOUNT a LEFT JOIN `TRANSACTION` t ON t.AccountID=a.AccountID
GROUP BY a.AccountID, a.AccountNumber ORDER BY a.AccountNumber;

-- 3. Customers who hold more than one account.
SELECT c.CustomerID, c.FirstName, c.LastName, fn_customer_account_count(c.CustomerID) AS AccountCount
FROM CUSTOMER c WHERE fn_customer_account_count(c.CustomerID) > 1;

-- 4. Total deposits recorded this calendar month.
SELECT COALESCE(SUM(Amount),0) AS MonthlyDeposits FROM `TRANSACTION`
WHERE TransactionType='DEPOSIT' AND TransactionDate >= DATE_FORMAT(CURDATE(),'%Y-%m-01');

-- 5. Accounts with balances above the overall average balance.
SELECT AccountNumber, AccountType, Balance FROM ACCOUNT
WHERE Balance > (SELECT AVG(Balance) FROM ACCOUNT) ORDER BY Balance DESC;

-- 6. Branch-wise count of accounts and total deposited balance.
SELECT b.BranchID, b.BranchName, COUNT(a.AccountID) AS AccountCount,
       COALESCE(SUM(a.Balance),0) AS TotalBranchBalance
FROM BRANCH b LEFT JOIN ACCOUNT a ON a.BranchID=b.BranchID
GROUP BY b.BranchID, b.BranchName ORDER BY TotalBranchBalance DESC;

-- 7. Customers who have no bank account.
SELECT c.CustomerID, c.FirstName, c.LastName, c.Mobile FROM CUSTOMER c
LEFT JOIN ACCOUNT_HOLDER ah ON ah.CustomerID=c.CustomerID WHERE ah.AccountID IS NULL;

-- 8. Loan portfolio and amount paid per loan.
SELECT * FROM v_loan_payment_summary ORDER BY LoanAmount DESC;

-- 9. Employees and their branch contact details.
SELECT e.EmployeeID, e.EmployeeName, e.Designation, e.Salary, b.BranchName, b.City, b.ContactNumber
FROM EMPLOYEE e JOIN BRANCH b ON b.BranchID=e.BranchID ORDER BY b.BranchName, e.EmployeeName;

-- 10. Most recent successful transactions with customer names.
SELECT t.TransactionID, t.TransactionDate, t.TransactionType, t.Amount, t.ReferenceNumber,
       a.AccountNumber, GROUP_CONCAT(CONCAT(c.FirstName,' ',c.LastName) SEPARATOR ', ') AS AccountHolders
FROM `TRANSACTION` t JOIN ACCOUNT a ON a.AccountID=t.AccountID
LEFT JOIN ACCOUNT_HOLDER ah ON ah.AccountID=a.AccountID
LEFT JOIN CUSTOMER c ON c.CustomerID=ah.CustomerID
WHERE t.TransactionStatus='SUCCESS'
GROUP BY t.TransactionID, t.TransactionDate, t.TransactionType, t.Amount, t.ReferenceNumber, a.AccountNumber
ORDER BY t.TransactionDate DESC LIMIT 50;

-- 11. Accounts with no transactions.
SELECT a.AccountID, a.AccountNumber, a.Balance FROM ACCOUNT a
LEFT JOIN `TRANSACTION` t ON t.AccountID=a.AccountID WHERE t.TransactionID IS NULL;

-- 12. Count loans by type and sum the approved loan amounts.
SELECT LoanType, COUNT(*) AS LoanCount, SUM(LoanAmount) AS TotalLoanAmount
FROM LOAN GROUP BY LoanType ORDER BY TotalLoanAmount DESC;

-- 13. Find loan payments recorded during the current year.
SELECT lp.PaymentID, lp.PaymentDate, lp.Amount, lp.PaymentMode, lp.ReferenceNumber,
       l.LoanID, l.LoanType, CONCAT(c.FirstName,' ',c.LastName) AS CustomerName
FROM LOAN_PAYMENT lp JOIN LOAN l ON l.LoanID=lp.LoanID
JOIN CUSTOMER c ON c.CustomerID=l.CustomerID
WHERE YEAR(lp.PaymentDate)=YEAR(CURDATE()) ORDER BY lp.PaymentDate DESC;
