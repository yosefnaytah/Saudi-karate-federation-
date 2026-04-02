// Base URL for API endpoints
// .NET backend typically runs on port 5000 (HTTP) or 5001 (HTTPS)
// Change this to match your backend port
const API_BASE_URL = 'http://localhost:5000/api';
const LOCAL_TEST_MODE = true;
const LOCAL_USERS_KEY = 'skf_local_users';

function getDashboardUrl(role) {
    switch ((role || '').toLowerCase()) {
        case 'admin':
            return 'admin-dashboard.html';
        case 'player':
            return 'player-dashboard.html';
        case 'coach':
        case 'referee':
        case 'club_admin':
        case 'referees_plus':
            // Dedicated pages are not created yet, so use player dashboard temporarily.
            return 'player-dashboard.html';
        default:
            return 'player-dashboard.html';
    }
}

function getLocalUsers() {
    try {
        return JSON.parse(localStorage.getItem(LOCAL_USERS_KEY) || '[]');
    } catch {
        return [];
    }
}

function setLocalUsers(users) {
    localStorage.setItem(LOCAL_USERS_KEY, JSON.stringify(users));
}

// Login form submission handler
async function handleLogin(event) {
    event.preventDefault();
    
    const email = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;

    if (LOCAL_TEST_MODE) {
        const users = getLocalUsers();
        const matchedUser = users.find(
            (u) => (u.email || '').toLowerCase() === email.toLowerCase() && u.password === password
        );

        if (!matchedUser) {
            alert('Invalid credentials');
            return false;
        }

        localStorage.setItem('token', `local-token-${Date.now()}`);
        localStorage.setItem('user', JSON.stringify({
            id: matchedUser.id,
            email: matchedUser.email,
            fullName: matchedUser.fullName,
            role: matchedUser.role,
            username: matchedUser.username || matchedUser.email
        }));

        alert('Login successful! Welcome ' + matchedUser.fullName + ' (Local Test Mode)');
        window.location.href = getDashboardUrl(matchedUser.role);
        return false;
    }

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
            window.location.href = getDashboardUrl(data.user.role);
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
    const email = String(formData.get('email') || '').trim();
    const nationalId = String(formData.get('national-id') || '').trim();
    const userData = {
        fullName: formData.get('full-name'),
        nationalId: nationalId,
        playerId: nationalId,
        phone: formData.get('phone'),
        clubName: formData.get('club-name'),
        email: email,
        username: email,
        password: formData.get('password'),
        confirmPassword: formData.get('confirm-password'),
        role: formData.get('user-role')
    };

    if (LOCAL_TEST_MODE) {
        const allowedRoles = ['player', 'coach', 'referee', 'club_admin', 'referees_plus'];
        const role = String(userData.role || '').toLowerCase();
        const users = getLocalUsers();

        if (!allowedRoles.includes(role)) {
            alert('Please select a valid role.');
            return false;
        }

        const existing = users.find((u) => (u.email || '').toLowerCase() === userData.email.toLowerCase());
        if (existing) {
            alert('This email is already registered (Local Test Mode).');
            return false;
        }

        users.push({
            id: `local-${Date.now()}`,
            fullName: userData.fullName,
            nationalId: userData.nationalId,
            playerId: userData.playerId,
            phone: userData.phone,
            clubName: userData.clubName,
            email: userData.email,
            username: userData.username,
            password: userData.password,
            role
        });
        setLocalUsers(users);

        alert('Registration successful (Local Test Mode)! Please login.');
        window.location.href = 'index.html';
        return false;
    }

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
            const errorDetails = data.error ? `\nDetails: ${data.error}` : '';
            alert((data.message || 'Registration failed') + errorDetails);
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
    
    if (!token || !user) {
        return false;
    }
    return true;
}

// Display user info on dashboard
function displayUserInfo() {
    const user = JSON.parse(localStorage.getItem('user') || '{}');
    const userDisplayElement = document.getElementById('userDisplay');
    
    if (userDisplayElement && user.fullName) {
        // Format role name for display
        const roleDisplay = formatRoleName(user.role);
        userDisplayElement.textContent = `Welcome, ${user.fullName} (${roleDisplay})`;
    }
}

// Format role name for display
function formatRoleName(role) {
    if (!role) return 'User';
    
    const roleMap = {
        'admin': 'SKF Admin',
        'player': 'Player',
        'coach': 'Coach',
        'referee': 'Referee',
        'club_admin': 'Club Admin',
        'referees_plus': 'Referees +'
    };
    
    return roleMap[role.toLowerCase()] || role;
}
