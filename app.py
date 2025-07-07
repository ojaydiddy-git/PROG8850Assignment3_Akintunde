##Flask app for testing selenium and MySQL database---Optional

#app.py

from flask import Flask, request, render_template_string
import mysql.connector
import os

app = Flask(__name__)

# Database connection
def get_db_connection():
    return mysql.connector.connect(
        user= os.environ.get("DB_USER",  "root"),
        password=os.environ.get("DB_PASSWORD", "Secret5555"),
        host= os.environ.get("DB_HOST", "127.0.0.1"),
        database=os.environ.get("DB_NAME", "firstdatabase")
    )

# Simple login page
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        # For demonstration, assume login is successful and insert into the database
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

