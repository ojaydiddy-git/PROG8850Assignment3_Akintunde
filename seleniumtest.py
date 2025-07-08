from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.chrome.options import Options
import time

# Set Chrome options for headless mode
chrome_options = Options()
chrome_options.add_argument("--headless")  # Run without GUI
chrome_options.add_argument("--no-sandbox")
chrome_options.add_argument("--disable-dev-shm-usage")

# Create driver
driver = webdriver.Chrome(options=chrome_options)

try:
    # Open login form
    driver.get("http://127.0.0.1:5000/login")

    # Fill the form
    driver.find_element(By.NAME, "username").send_keys("testuser")
    driver.find_element(By.NAME, "password").send_keys("testpass")

    # Submit
    driver.find_element(By.CSS_SELECTOR, "input[type='submit']").click()

    time.sleep(1)  # Allow time for page to update

    # Validate output
    body = driver.page_source
    if "Login Successful" in body:
        print("✅ Selenium Test Passed: Login form submission works.")
    else:
        print("❌ Test Failed: Unexpected response.")

except Exception as e:
    print(f"❌ Test Failed with error: {e}")

finally:
    driver.quit()
