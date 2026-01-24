// Base URL for API endpoints
const API_BASE_URL = 'http://localhost:3000/api';

// Login form submission handler
async function handleLogin(event) {
    event.preventDefault();
    
    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;

    try {
        const response = await fetch(`${API_BASE_URL}/auth/login`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                email: email,
                password: password
            })
        });

        const data = await response.json();

        if (response.ok) {
            // Login successful
            localStorage.setItem('token', data.token);
            localStorage.setItem('user', JSON.stringify(data.user));
            alert('Login successful! Welcome ' + data.user.fullName);
            // Redirect to dashboard or main page
            window.location.href = 'player-dashboard.html';
        } else {
            // Login failed
            alert(data.message || 'Login failed');
        }
    } catch (error) {
        console.error('Error:', error);
        alert('An error occurred during login');
    }
}

// Register form submission handler
async function handleRegister(event) {
    event.preventDefault();
    
    // First validate the form
    if (!validateForm(event)) {
        return false;
    }
    
    const formData = new FormData(event.target);
    const userData = {
        fullName: formData.get('full-name'),
        nationalId: formData.get('national-id'),
        playerId: formData.get('player-id'),
        phone: formData.get('phone'),
        clubName: formData.get('club-name'),
        email: formData.get('email'),
        username: formData.get('username'),
        password: formData.get('password'),
        confirmPassword: formData.get('confirm-password'),
        role: formData.get('user-role')
    };

    try {
        const response = await fetch(`${API_BASE_URL}/auth/register`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(userData)
        });

        const data = await response.json();

        if (response.ok) {
            // Registration successful
            alert('Registration successful! Please login with your credentials.');
            // Redirect to login page
            window.location.href = 'index.html';
        } else {
            // Registration failed
            alert(data.message || 'Registration failed');
        }
    } catch (error) {
        console.error('Error:', error);
        alert('An error occurred during registration');
    }
    
    return false;
}

// Logout function
function logout() {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    alert('Logged out successfully!');
    window.location.href = 'index.html';
}

// Check if user is logged in
function checkAuth() {
    const token = localStorage.getItem('token');
    const user = localStorage.getItem('user');
    
    // For development/testing: Create demo user if no authentication data exists
    if (!token || !user) {
        // Set demo authentication data for testing
        const demoUser = {
            fullName: "Demo Player",
            email: "demo@skf.sa",
            role: "Player",
            playerId: "SKF001",
            clubName: "Demo Club"
        };
        localStorage.setItem('token', 'demo-token-' + Date.now());
        localStorage.setItem('user', JSON.stringify(demoUser));
        return true;
    }
    return true;
}

// Display user info on dashboard
function displayUserInfo() {
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    const userDisplayElement = document.getElementById('userDisplay');
    
    if (userDisplayElement && user.fullName) {
        userDisplayElement.textContent = `Welcome, ${user.fullName} (${user.role})`;
    }
}
