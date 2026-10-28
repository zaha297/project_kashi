
"""Project Kashi — Flask application backed by MySQL."""

import os
import re
import secrets
import hmac
from decimal import Decimal, InvalidOperation
from datetime import date

import mysql.connector
from mysql.connector import Error, IntegrityError, DatabaseError
from flask import (
    Flask,
    abort,
    flash,
    redirect,
    render_template,
    request,
    session,
    url_for,
    g,
)
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

app.config.update(
    SECRET_KEY=os.getenv(
        "FLASK_SECRET_KEY",
        "change-this-development-key-before-use",
    ),
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=(
        os.getenv("COOKIE_SECURE", "false").lower() == "true"
    ),
)

DB_CONFIG = {
    "host": os.getenv("MYSQL_HOST", "127.0.0.1"),
    "port": int(os.getenv("MYSQL_PORT", "3306")),
    "user": os.getenv("MYSQL_USER", "root"),
    "password": os.getenv("MYSQL_PASSWORD", "dbmsyen@123"),
    "database": os.getenv("MYSQL_DATABASE", "project_kashi"),
    "connection_timeout": 5,
}


# --------------------------------------------------
# DATABASE HELPERS
# --------------------------------------------------

def get_db():
    """Open one database connection for the current request."""
    if "db" not in g:
        g.db = mysql.connector.connect(**DB_CONFIG)
    return g.db


@app.teardown_appcontext
def close_db(_error=None):
    db = g.pop("db", None)

    if db is not None and db.is_connected():
        db.close()


def query_all(sql, params=()):
    conn = get_db()
    cursor = conn.cursor(dictionary=True)

    try:
        cursor.execute(sql, params)
        return cursor.fetchall()
    finally:
        cursor.close()


def query_one(sql, params=()):
    rows = query_all(sql, params)
    return rows[0] if rows else None


def execute(sql, params=(), commit=True):
    conn = get_db()
    cursor = conn.cursor()

    try:
        cursor.execute(sql, params)

        if commit:
            conn.commit()

        return cursor.lastrowid, cursor.rowcount

    except Exception:
        if commit:
            conn.rollback()
        raise

    finally:
        cursor.close()


# --------------------------------------------------
# CSRF PROTECTION
# --------------------------------------------------

def csrf_token():
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(32)

    return session["csrf_token"]


app.jinja_env.globals["csrf_token"] = csrf_token


@app.before_request
def protect_post_forms():
    if request.method == "POST":
        submitted = request.form.get("csrf_token", "")
        expected = session.get("csrf_token", "")

        if not expected or not hmac.compare_digest(
            submitted,
            expected,
        ):
            abort(
                400,
                description=(
                    "The form expired or could not be verified. "
                    "Please go back and try again."
                ),
            )


# --------------------------------------------------
# VALIDATION AND FORM HELPERS
# --------------------------------------------------

@app.template_filter("money")
def money(value):
    return f"₹{Decimal(str(value or 0)):,.2f}"


def required_text(field, label, max_length=120):
    value = request.form.get(field, "").strip()

    if not value:
        raise ValueError(f"{label} is required.")

    if len(value) > max_length:
        raise ValueError(
            f"{label} must be {max_length} characters or fewer."
        )

    return value


def optional_text(field, max_length=255):
    value = request.form.get(field, "").strip()

    if len(value) > max_length:
        raise ValueError(
            f"This field must be {max_length} characters or fewer."
        )

    return value or None


def positive_amount(field="amount"):
    raw = request.form.get(field, "").strip()

    try:
        amount = Decimal(raw)
    except (InvalidOperation, ValueError):
        raise ValueError("Enter a valid amount.")

    if (
        not amount.is_finite()
        or amount <= 0
        or amount.as_tuple().exponent < -2
    ):
        raise ValueError(
            "Amount must be positive and may have at most "
            "two decimal places."
        )

    if amount > Decimal("999999999999.99"):
        raise ValueError("Amount is too large.")

    return amount


def positive_int(field, label, minimum=1, maximum=600):
    try:
        value = int(request.form.get(field, ""))
    except (TypeError, ValueError):
        raise ValueError(f"Enter a valid {label.lower()}.")

    if not minimum <= value <= maximum:
        raise ValueError(
            f"{label} must be between {minimum} and {maximum}."
        )

    return value



def handle_form_error(exc):
    app.logger.exception("Registration/database error")

    if isinstance(exc, IntegrityError):
        flash(
            f"Database conflict: {exc}",
            "error",
        )
    elif isinstance(exc, (DatabaseError, Error)):
        flash(
            f"Database error: {exc}",
            "error",
        )
    else:
        flash(str(exc), "error")



# --------------------------------------------------
# ERROR PAGES
# --------------------------------------------------

@app.errorhandler(400)
def bad_request(error):
    return (
        render_template(
            "error.html",
            code=400,
            message=getattr(
                error,
                "description",
                "Invalid request.",
            ),
        ),
        400,
    )


@app.errorhandler(404)
def not_found(_error):
    return (
        render_template(
            "error.html",
            code=404,
            message="The requested record or page was not found.",
        ),
        404,
    )


@app.errorhandler(500)
def server_error(_error):
    return (
        render_template(
            "error.html",
            code=500,
            message=(
                "Something went wrong. "
                "Check the application terminal for details."
            ),
        ),
        500,
    )


# --------------------------------------------------
# DASHBOARD
# --------------------------------------------------

@app.route("/")
def index():
    try:
        counts = {
            "customers": query_one(
                "SELECT COUNT(*) AS n FROM CUSTOMER"
            )["n"],
            "accounts": query_one(
                "SELECT COUNT(*) AS n FROM ACCOUNT"
            )["n"],
            "branches": query_one(
                "SELECT COUNT(*) AS n FROM BRANCH"
            )["n"],
            "transactions": query_one(
                "SELECT COUNT(*) AS n FROM `TRANSACTION`"
            )["n"],
        }

        recent = query_all(
            """
            SELECT
                t.TransactionID,
                t.TransactionType,
                t.Amount,
                t.TransactionDate,
                t.TransactionStatus,
                t.ReferenceNumber,
                a.AccountNumber
            FROM `TRANSACTION` t
            JOIN ACCOUNT a
                ON a.AccountID = t.AccountID
            ORDER BY
                t.TransactionDate DESC,
                t.TransactionID DESC
            LIMIT 6
            """
        )

        db_error = None

    except Error as exc:
        counts = None
        recent = []
        db_error = str(exc)

    return render_template(
        "index.html",
        counts=counts,
        recent=recent,
        db_error=db_error,
    )


# --------------------------------------------------
# CUSTOMERS
# --------------------------------------------------

@app.route("/customers")
def customers():
    rows = query_all(
        "SELECT * FROM CUSTOMER ORDER BY CustomerID DESC"
    )

    account_rows = query_all(
        """
        SELECT CustomerID, COUNT(*) AS n
        FROM ACCOUNT_HOLDER
        GROUP BY CustomerID
        """
    )

    account_counts = {
        row["CustomerID"]: row["n"]
        for row in account_rows
    }

    return render_template(
        "customers.html",
        customers=rows,
        account_counts=account_counts,
    )


@app.route("/customers/new", methods=["GET", "POST"])
def customer_new():
    if request.method == "POST":
        try:
            first = required_text(
                "first_name", "First name", 60
            )
            last = required_text(
                "last_name", "Last name", 60
            )
            dob = required_text(
                "dob", "Date of birth"
            )
            gender = required_text(
                "gender", "Gender", 20
            )
            mobile = required_text(
                "mobile", "Mobile", 20
            )
            email = required_text(
                "email", "Email", 120
            ).lower()
            address = required_text(
                "address", "Address", 255
            )
            city = required_text(
                "city", "City", 80
            )

            if gender not in {
                "Female",
                "Male",
                "Other",
                "Prefer not to say",
            }:
                raise ValueError(
                    "Select a valid gender option."
                )

            if not re.fullmatch(
                r"[^\s@]+@[^\s@]+\.[^\s@]+",
                email,
            ):
                raise ValueError(
                    "Enter a valid email address."
                )

            if not re.fullmatch(
                r"[0-9+() -]{7,20}",
                mobile,
            ):
                raise ValueError(
                    "Enter a valid mobile number."
                )

            try:
                birth_date = date.fromisoformat(dob)
            except ValueError:
                raise ValueError(
                    "Enter a valid date of birth."
                )

            if birth_date >= date.today():
                raise ValueError(
                    "Date of birth must be in the past."
                )

            customer_id, _ = execute(
                """
                INSERT INTO CUSTOMER
                    (
                        FirstName,
                        LastName,
                        DOB,
                        Gender,
                        Mobile,
                        Email,
                        Address,
                        City
                    )
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    first,
                    last,
                    dob,
                    gender,
                    mobile,
                    email,
                    address,
                    city,
                ),
            )

            next_step = request.form.get(
                "next_step",
                "later",
            )

            flash(
                f"Customer registered successfully. "
                f"Customer ID: {customer_id:05d}.",
                "success",
            )

            if next_step == "create_account":
                return redirect(
                    url_for(
                        "account_new",
                        customer_id=customer_id,
                    )
                )

            return redirect(url_for("customers"))

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    return render_template("customer_form.html")


# --------------------------------------------------
# BRANCHES
# --------------------------------------------------

@app.route("/branches")
def branches():
    rows = query_all(
        """
        SELECT
            b.*,
            (
                SELECT COUNT(*)
                FROM ACCOUNT a
                WHERE a.BranchID = b.BranchID
            ) AS AccountCount
        FROM BRANCH b
        ORDER BY BranchName
        """
    )

    return render_template(
        "branches.html",
        branches=rows,
    )


@app.route("/branches/new", methods=["GET", "POST"])
def branch_new():
    if request.method == "POST":
        try:
            branch_name = required_text(
                "branch_name", "Branch name", 100
            )
            ifsc = required_text(
                "ifsc", "IFSC code", 11
            ).upper()
            address = required_text(
                "address", "Address", 255
            )
            city = required_text(
                "city", "City", 80
            )
            state = required_text(
                "state", "State", 80
            )
            contact = required_text(
                "contact", "Contact number", 20
            )

            if not re.fullmatch(
                r"[A-Z]{4}0[A-Z0-9]{6}",
                ifsc,
            ):
                raise ValueError(
                    "Enter an 11-character IFSC code "
                    "in the standard format."
                )

            execute(
                """
                INSERT INTO BRANCH
                    (
                        BranchName,
                        IFSCCode,
                        Address,
                        City,
                        State,
                        ContactNumber
                    )
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (
                    branch_name,
                    ifsc,
                    address,
                    city,
                    state,
                    contact,
                ),
            )

            flash("Branch saved to MySQL.", "success")
            return redirect(url_for("branches"))

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    return render_template("branch_form.html")


# --------------------------------------------------
# EMPLOYEES
# --------------------------------------------------

@app.route("/employees")
def employees():
    rows = query_all(
        """
        SELECT e.*, b.BranchName
        FROM EMPLOYEE e
        JOIN BRANCH b
            ON b.BranchID = e.BranchID
        ORDER BY e.EmployeeID DESC
        """
    )

    return render_template(
        "employees.html",
        employees=rows,
    )


@app.route("/employees/new", methods=["GET", "POST"])
def employee_new():
    branch_options = query_all(
        """
        SELECT BranchID, BranchName
        FROM BRANCH
        ORDER BY BranchName
        """
    )

    if request.method == "POST":
        try:
            name = required_text(
                "employee_name", "Employee name", 120
            )
            mobile = required_text(
                "mobile", "Mobile", 20
            )
            email = required_text(
                "email", "Email", 120
            ).lower()
            designation = required_text(
                "designation", "Designation", 80
            )
            salary = positive_amount("salary")
            joining = required_text(
                "joining_date", "Joining date"
            )
            branch_id = positive_int(
                "branch_id", "Branch ID"
            )

            if not re.fullmatch(
                r"[^\s@]+@[^\s@]+\.[^\s@]+",
                email,
            ):
                raise ValueError(
                    "Enter a valid email address."
                )

            if not query_one(
                "SELECT BranchID FROM BRANCH WHERE BranchID = %s",
                (branch_id,),
            ):
                raise ValueError(
                    "Select an existing branch."
                )

            execute(
                """
                INSERT INTO EMPLOYEE
                    (
                        EmployeeName,
                        Mobile,
                        Email,
                        Designation,
                        Salary,
                        JoiningDate,
                        BranchID
                    )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    name,
                    mobile,
                    email,
                    designation,
                    salary,
                    joining,
                    branch_id,
                ),
            )

            flash("Employee saved to MySQL.", "success")
            return redirect(url_for("employees"))

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    return render_template(
        "employee_form.html",
        branches=branch_options,
    )


# --------------------------------------------------
# ACCOUNTS
# --------------------------------------------------

@app.route("/accounts")
def accounts():
    rows = query_all(
        """
        SELECT
            a.*,
            b.BranchName,
            GROUP_CONCAT(
                CONCAT(c.FirstName, ' ', c.LastName)
                ORDER BY c.CustomerID
                SEPARATOR ', '
            ) AS Holders
        FROM ACCOUNT a
        JOIN BRANCH b
            ON b.BranchID = a.BranchID
        LEFT JOIN ACCOUNT_HOLDER ah
            ON ah.AccountID = a.AccountID
        LEFT JOIN CUSTOMER c
            ON c.CustomerID = ah.CustomerID
        GROUP BY a.AccountID
        ORDER BY a.AccountID DESC
        """
    )

    return render_template(
        "accounts.html",
        accounts=rows,
    )


@app.route("/accounts/lookup", methods=["POST"])
def account_lookup():
    """Find an account using its complete account number."""
    account_number = request.form.get(
        "account_number", ""
    ).strip().upper()

    if not account_number:
        flash(
            "Enter an account number to search.",
            "error",
        )
        return redirect(url_for("accounts"))

    account = query_one(
        """
        SELECT AccountID
        FROM ACCOUNT
        WHERE AccountNumber = %s
        """,
        (account_number,),
    )

    if not account:
        flash(
            "No account was found with that account number. "
            "Check it and try again.",
            "error",
        )
        return redirect(url_for("accounts"))

    return redirect(
        url_for(
            "account_detail",
            account_id=account["AccountID"],
        )
    )


@app.route("/accounts/new", methods=["GET", "POST"])
def account_new():
    customer_options = query_all(
        """
        SELECT CustomerID, FirstName, LastName
        FROM CUSTOMER
        ORDER BY FirstName, LastName
        """
    )

    branch_options = query_all(
        """
        SELECT BranchID, BranchName, IFSCCode
        FROM BRANCH
        ORDER BY BranchName
        """
    )

    selected_customer_id = request.args.get(
        "customer_id",
        type=int,
    )

    if request.method == "POST":
        try:
            customer_id = positive_int(
                "customer_id", "Customer"
            )
            branch_id = positive_int(
                "branch_id", "Branch"
            )
            account_type = required_text(
                "account_type", "Account type", 20
            )

            opening_raw = (
                request.form.get(
                    "opening_balance", "0"
                ).strip()
                or "0"
            )

            try:
                opening = Decimal(opening_raw)
            except (InvalidOperation, ValueError):
                raise ValueError(
                    "Enter a valid initial deposit amount."
                )

            if (
                not opening.is_finite()
                or opening < 0
                or opening.as_tuple().exponent < -2
            ):
                raise ValueError(
                    "Initial deposit must be zero or positive "
                    "and may have at most two decimal places."
                )

            if opening > Decimal("999999999999.99"):
                raise ValueError(
                    "Initial deposit is too large."
                )

            if account_type not in {
                "Saving",
                "Current",
                "Salary",
            }:
                raise ValueError(
                    "Select a valid account type."
                )

            if not query_one(
                """
                SELECT CustomerID
                FROM CUSTOMER
                WHERE CustomerID = %s
                """,
                (customer_id,),
            ):
                raise ValueError(
                    "Select an existing customer."
                )

            if not query_one(
                """
                SELECT BranchID
                FROM BRANCH
                WHERE BranchID = %s
                """,
                (branch_id,),
            ):
                raise ValueError(
                    "Select an existing branch."
                )

            conn = get_db()
            cursor = conn.cursor()

            try:

                # Generate a 12-character account number.
                account_number = (
                    "KSH"
                    + secrets.token_hex(5).upper()[:9]
                )

                cursor.execute(
                    """
                    INSERT INTO ACCOUNT
                        (
                            AccountNumber,
                            AccountType,
                            OpeningDate,
                            Balance,
                            Status,
                            BranchID
                        )
                    VALUES (
                        %s, %s, CURDATE(), 0.00,
                        'Active', %s
                    )
                    """,
                    (
                        account_number,
                        account_type,
                        branch_id,
                    ),
                )

                account_id = cursor.lastrowid

                # Link the account to its customer.
                cursor.execute(
                    """
                    INSERT INTO ACCOUNT_HOLDER
                        (
                            CustomerID,
                            AccountID,
                            HolderSince,
                            HolderType
                        )
                    VALUES (
                        %s, %s, CURDATE(), 'Primary'
                    )
                    """,
                    (customer_id, account_id),
                )

                conn.commit()

            except Exception:
                conn.rollback()
                raise

            finally:
                cursor.close()

            # Record the initial deposit through the procedure.
            if opening > 0:
                execute(
                    "CALL sp_deposit(%s, %s, %s)",
                    (
                        account_id,
                        opening,
                        "Initial opening deposit",
                    ),
                )

            flash(
                f"Account {account_number} created "
                "and saved to MySQL.",
                "success",
            )

            return redirect(
                url_for(
                    "account_detail",
                    account_id=account_id,
                )
            )

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    return render_template(
        "account_form.html",
        customers=customer_options,
        branches=branch_options,
        selected_customer_id=selected_customer_id,
    )


@app.route("/accounts/<int:account_id>")
def account_detail(account_id):
    account = query_one(
        """
        SELECT
            a.*,
            b.BranchName,
            b.IFSCCode,
            GROUP_CONCAT(
                CONCAT(c.FirstName, ' ', c.LastName)
                SEPARATOR ', '
            ) AS Holders
        FROM ACCOUNT a
        JOIN BRANCH b
            ON b.BranchID = a.BranchID
        LEFT JOIN ACCOUNT_HOLDER ah
            ON ah.AccountID = a.AccountID
        LEFT JOIN CUSTOMER c
            ON c.CustomerID = ah.CustomerID
        WHERE a.AccountID = %s
        GROUP BY a.AccountID
        """,
        (account_id,),
    )

    if not account:
        abort(404)

    history = query_all(
        """
        SELECT *
        FROM `TRANSACTION`
        WHERE AccountID = %s
        ORDER BY TransactionDate DESC, TransactionID DESC
        LIMIT 30
        """,
        (account_id,),
    )

    return render_template(
        "account_detail.html",
        account=account,
        history=history,
    )


# --------------------------------------------------
# TRANSACTIONS
# --------------------------------------------------

@app.route("/transactions")
def transactions():
    rows = query_all(
        """
        SELECT
            t.*,
            a.AccountNumber
        FROM `TRANSACTION` t
        JOIN ACCOUNT a
            ON a.AccountID = t.AccountID
        ORDER BY
            t.TransactionDate DESC,
            t.TransactionID DESC
        LIMIT 250
        """
    )

    return render_template(
        "transactions.html",
        transactions=rows,
    )


@app.route("/transactions/new", methods=["GET", "POST"])
def transaction_new():
    account_options = query_all(
        """
        SELECT AccountID, AccountNumber, Balance, Status
        FROM ACCOUNT
        ORDER BY AccountID DESC
        """
    )

    if request.method == "POST":
        try:
            kind = required_text(
                "transaction_type",
                "Transaction type",
                20,
            )

            if kind not in {
                "DEPOSIT",
                "WITHDRAWAL",
                "TRANSFER",
            }:
                raise ValueError(
                    "Select a valid transaction type."
                )

            source = positive_int(
                "account_id", "Account"
            )
            amount = positive_amount()

            description = (
                optional_text("description", 255)
                or kind.replace("_", " ").title()
            )

            source_row = query_one(
                """
                SELECT AccountID, Status
                FROM ACCOUNT
                WHERE AccountID = %s
                """,
                (source,),
            )

            if not source_row:
                raise ValueError(
                    "Select an existing source account."
                )

            if source_row["Status"] != "Active":
                raise ValueError(
                    "Only active accounts can transact."
                )

            conn = get_db()
            cursor = conn.cursor()

            try:
                if kind == "DEPOSIT":
                    cursor.callproc(
                        "sp_deposit",
                        (source, amount, description),
                    )

                elif kind == "WITHDRAWAL":
                    cursor.callproc(
                        "sp_withdraw",
                        (source, amount, description),
                    )

                else:
                    destination = positive_int(
                        "destination_account_id",
                        "Destination account",
                    )

                    if source == destination:
                        raise ValueError(
                            "Source and destination accounts "
                            "must be different."
                        )

                    cursor.callproc(
                        "sp_transfer",
                        (
                            source,
                            destination,
                            amount,
                            description,
                        ),
                    )

                conn.commit()

            except Exception:
                conn.rollback()
                raise

            finally:
                cursor.close()

            flash(
                "Transaction completed and recorded in MySQL.",
                "success",
            )

            return redirect(url_for("transactions"))

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    return render_template(
        "transaction_form.html",
        accounts=account_options,
    )


# --------------------------------------------------
# LOANS
# --------------------------------------------------

@app.route("/loans")
def loans():
    rows = query_all(
        """
        SELECT
            l.*,
            CONCAT(c.FirstName, ' ', c.LastName)
                AS CustomerName,
            b.BranchName,
            COALESCE(
                (
                    SELECT SUM(lp.Amount)
                    FROM LOAN_PAYMENT lp
                    WHERE lp.LoanID = l.LoanID
                ),
                0
            ) AS PaidAmount
        FROM LOAN l
        JOIN CUSTOMER c
            ON c.CustomerID = l.CustomerID
        JOIN BRANCH b
            ON b.BranchID = l.BranchID
        ORDER BY l.LoanID DESC
        """
    )

    return render_template(
        "loans.html",
        loans=rows,
    )


@app.route("/loans/new", methods=["GET", "POST"])
def loan_new():
    customer_options = query_all(
        """
        SELECT CustomerID, FirstName, LastName
        FROM CUSTOMER
        ORDER BY FirstName, LastName
        """
    )

    branch_options = query_all(
        """
        SELECT BranchID, BranchName
        FROM BRANCH
        ORDER BY BranchName
        """
    )

    if request.method == "POST":
        try:
            customer_id = positive_int(
                "customer_id", "Customer"
            )
            branch_id = positive_int(
                "branch_id", "Branch"
            )
            loan_type = required_text(
                "loan_type", "Loan type", 40
            )
            amount = positive_amount("loan_amount")

            try:
                rate = Decimal(
                    required_text(
                        "interest_rate",
                        "Interest rate",
                    )
                )
            except (InvalidOperation, ValueError):
                raise ValueError(
                    "Enter a valid interest rate."
                )

            if (
                not rate.is_finite()
                or rate < 0
                or rate > 100
            ):
                raise ValueError(
                    "Interest rate must be between 0 and 100."
                )

            tenure = positive_int(
                "tenure",
                "Tenure in months",
                1,
                600,
            )

            start = required_text(
                "start_date", "Start date"
            )

            if loan_type not in {
                "Home Loan",
                "Education Loan",
                "Personal Loan",
                "Vehicle Loan",
            }:
                raise ValueError(
                    "Select a valid loan type."
                )

            if not query_one(
                """
                SELECT CustomerID
                FROM CUSTOMER
                WHERE CustomerID = %s
                """,
                (customer_id,),
            ):
                raise ValueError(
                    "Select an existing customer."
                )

            if not query_one(
                """
                SELECT BranchID
                FROM BRANCH
                WHERE BranchID = %s
                """,
                (branch_id,),
            ):
                raise ValueError(
                    "Select an existing branch."
                )

            execute(
                """
                INSERT INTO LOAN
                    (
                        CustomerID,
                        BranchID,
                        LoanType,
                        LoanAmount,
                        InterestRate,
                        StartDate,
                        TenureMonths,
                        LoanStatus
                    )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, 'Active'
                )
                """,
                (
                    customer_id,
                    branch_id,
                    loan_type,
                    amount,
                    rate,
                    start,
                    tenure,
                ),
            )

            flash("Loan record saved to MySQL.", "success")
            return redirect(url_for("loans"))

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    return render_template(
        "loan_form.html",
        customers=customer_options,
        branches=branch_options,
    )


# --------------------------------------------------
# LOAN PAYMENTS
# --------------------------------------------------

@app.route(
    "/loans/<int:loan_id>/payments",
    methods=["GET", "POST"],
)
def loan_payments(loan_id):
    loan = query_one(
        """
        SELECT
            l.*,
            CONCAT(c.FirstName, ' ', c.LastName)
                AS CustomerName,
            COALESCE(
                (
                    SELECT SUM(lp.Amount)
                    FROM LOAN_PAYMENT lp
                    WHERE lp.LoanID = l.LoanID
                ),
                0
            ) AS PaidAmount
        FROM LOAN l
        JOIN CUSTOMER c
            ON c.CustomerID = l.CustomerID
        WHERE l.LoanID = %s
        """,
        (loan_id,),
    )

    if not loan:
        abort(404)

    if request.method == "POST":
        try:
            amount = positive_amount()

            mode = required_text(
                "payment_mode", "Payment mode", 30
            )

            reference = optional_text(
                "reference_number", 80
            )

            if mode not in {
                "Cash",
                "UPI",
                "Bank Transfer",
                "Cheque",
                "Other",
            }:
                raise ValueError(
                    "Select a valid payment mode."
                )

            if loan["LoanStatus"] != "Active":
                raise ValueError(
                    "Payments can only be recorded "
                    "for active loans."
                )

            execute(
                """
                INSERT INTO LOAN_PAYMENT
                    (
                        LoanID,
                        PaymentDate,
                        Amount,
                        PaymentMode,
                        ReferenceNumber
                    )
                VALUES (%s, CURDATE(), %s, %s, %s)
                """,
                (
                    loan_id,
                    amount,
                    mode,
                    reference,
                ),
            )

            flash(
                "Loan payment recorded in MySQL.",
                "success",
            )

            return redirect(
                url_for(
                    "loan_payments",
                    loan_id=loan_id,
                )
            )

        except (ValueError, Error) as exc:
            handle_form_error(exc)

    payments = query_all(
        """
        SELECT *
        FROM LOAN_PAYMENT
        WHERE LoanID = %s
        ORDER BY PaymentDate DESC, PaymentID DESC
        """,
        (loan_id,),
    )

    return render_template(
        "loan_payments.html",
        loan=loan,
        payments=payments,
    )


# --------------------------------------------------
# DATABASE CONNECTION CHECK
# --------------------------------------------------

@app.route("/health")
def health():
    try:
        row = query_one(
            "SELECT DATABASE() AS db_name, VERSION() AS version"
        )

        return render_template(
            "health.html",
            connected=True,
            details=row,
            error=None,
        )

    except Error as exc:
        return (
            render_template(
                "health.html",
                connected=False,
                details=None,
                error=str(exc),
            ),
            503,
        )


# --------------------------------------------------
# START THE APPLICATION
# --------------------------------------------------

if __name__ == "__main__":
    app.run(
        host=os.getenv("FLASK_HOST", "127.0.0.1"),
        port=int(os.getenv("FLASK_PORT", "5000")),
        debug=(
            os.getenv("FLASK_DEBUG", "false").lower()
            == "true"
        ),
    )
