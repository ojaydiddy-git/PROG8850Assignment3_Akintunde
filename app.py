from flask import Flask, request
from dotenv import load_dotenv
import os
import MySQLdb

# Load environment variables from .env file
load_dotenv()

app = Flask(__name__)

# Database connection
def get_db_connection():
    return MySQLdb.connect(
        host=os.getenv("DATABASE_HOST"),
        user=os.getenv("DATABASE_USERNAME"),
        passwd=os.getenv("DATABASE_PASSWORD"),
        db=os.getenv("DATABASE"),
        autocommit=True,
        ssl_mode="VERIFY_IDENTITY",
        ssl={ "ca": "/etc/ssl/certs/ca-certificates.crt" }  # This path works in Codespaces
    )

# Home route
@app.route('/')
def index():
    return '''
        <h2>Welcome to the Login App</h2>
        <p><a href="/login">Go to Login</a></p>
    '''

# Login route
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("INSERT INTO users (username, password) VALUES (%s, %s)", (username, password))
        conn.commit()
        cursor.close()
        conn.close()
        return "Login Successful"
    return '''
        <form method="post">
            username: <input type="text" name="username"><br>
            password: <input type="password" name="password"><br>
            <input type="submit" value="Login">
        </form>
    '''

if __name__ == '__main__':
    app.run(debug=True)
