const API = "https://mmlifecaremedicalledger.onrender.com";

function addEntry() {
    const name = document.getElementById("name").value.trim();
    const phone = document.getElementById("phone").value.trim();
    const purchaseInput = document.getElementById("purchase").value;
    const paymentInput = document.getElementById("payment").value;
    const date = document.getElementById("date").value;
    

    if (!name) {
        alert("Enter customer name");
        return;
    }

    if (purchaseInput === "" && paymentInput === "") {
        alert("Enter purchase or payment");
        return;
    }

    if (purchaseInput < 0 || paymentInput < 0) {
        alert("Negative values not allowed");
        return;
    }

    const purchase = parseFloat(purchaseInput) || 0;
    const payment = parseFloat(paymentInput) || 0;

    const cleanPhone = phone.replace(/\D/g, "");
    if (phone && cleanPhone.length !== 10) {
        alert("Enter valid 10-digit phone number");
        return;
    }

    fetch(`${API}/add_entry`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },

        body: JSON.stringify({
            customer_name: name,
            phone: cleanPhone || null,
            current_purchase: purchase,
            payment: payment,
            date: date 
        })
    })
    .then(res => res.json())
    .then(data => {
        console.log("RESPONSE:", data);  // DEBUG

        if (data.message) {
            document.getElementById("result").innerText = 
                "Balance: " + data.balance;

            loadEntries();

            setTimeout(() => {
                loadSummary();
                loadTotalDashboard();
            }, 300);

            document.getElementById("purchase").value = "";
            document.getElementById("payment").value = "";

            alert(data.message);  
            showSuccessPopup();

        } else {
            document.getElementById("result").innerText =
                "Error: " + (data.error || "Unknown issue");       
        }
    })
    .catch(err => {
        console.error(err);
        document.getElementById("result").innerText = "Request failed";
            
    });
}

function loadEntries() {
    fetch(`${API}/get_entries`)
    .then(res => res.json())
    .then(data => {
        const tbody = document.querySelector("#ledgerTable tbody");
        if (!Array.isArray(data) || !data.length) {
            tbody.innerHTML = "<tr><td colspan='10'>No data</td></tr>";
            return;
        }
        tbody.innerHTML = "";

        data.forEach(e => {
            const row = `
                <tr class="${e.balance > 0 ? 'row-neg' : e.balance < 0 ? 'row-pos' : 'row-zero'}">
                    <td>${e.date}</td>
                    <td>${e.name}</td>
                    <td>${e.phone || "-"}</td>
                    <td>${e.previous}</td>
                    <td>${e.purchase}</td>
                    <td>${e.total}</td>
                    <td>${e.payment}</td>
                    <td class="${e.balance > 0 ? 'neg' : e.balance < 0 ? 'pos' : 'zero'}">
                        ${e.balance}
                        <div class="badge">
                            ${e.balance > 0 ? 'Due' : e.balance < 0 ? 'Advance' : 'Settled'}
                        </div>
                    </td>
                    <td>
                        <button onclick='editEntry(${JSON.stringify(e)})'>Edit</button>
                        <button onclick="deleteEntry(${e.id})" style="background:red;">Delete</button>
                    </td>
 
                    <td>
                        <button onclick="sendWhatsApp('${e.name}', ${e.balance}, '${e.phone || ""}')" style="background:#25D366;">
                            WhatsApp
                        </button>

                        <button onclick="sendSMS('${e.name}', ${e.balance}, '${e.phone || ""}')"
                                style="background:#007bff;">
                            SMS
                        </button>
                    </td>
                </tr>
            `;
            tbody.innerHTML += row;
        });
    });
}

function editEntry(entry) {

    const newDate = prompt("Edit Date (YYYY-MM-DDTHH:MM)", entry.date.replace(" ", "T"));
    if (newDate === null) return;

    const newName = prompt("Edit Name", entry.name);
    if (newName === null) return;

    const newPurchase = prompt("Edit Purchase", entry.purchase);
    if (newPurchase === null) return;

    const newPayment = prompt("Edit Payment", entry.payment);
    if (newPayment === null) return;

    fetch(`${API}/update_entry/${entry.id}`, {
        method: "PUT",
        headers: {
            "Content-Type": "application/json"
        },
        body: JSON.stringify({
            date: newDate,
            customer_name: newName,
            current_purchase: parseFloat(newPurchase) || 0,
            payment: parseFloat(newPayment) || 0
        })
    })
    .then(res => res.json())
    .then(() => {
        loadEntries();

        setTimeout(() => {
            loadSummary();
            loadTotalDashboard();
        }, 300); 
    });
}

function deleteEntry(id) {
    if (!confirm("Are you sure to delete?")) return;

    fetch(`${API}/delete_entry/${id}`, {
        method: "DELETE"
    })
    .then(res => res.json())
    .then(() => {
        loadEntries();


        setTimeout(() => {
            loadSummary();
            loadTotalDashboard();
        }, 300);
    });
}

function animateValue(id, start, end, duration = 500) {

    const element = document.getElementById(id);
    const range = end - start;
    let startTime = null;

    function step(timestamp) {
        if (!startTime) startTime = timestamp;
        const progress = Math.min((timestamp - startTime) / duration, 1);
        element.innerText = "₹ " + Number(Math.floor(progress * range + start)).toLocaleString("en-IN");

        if (progress < 1) {
            window.requestAnimationFrame(step);
        } else {
            element.innerText = "₹ " + Number(end).toLocaleString("en-IN");
        }
    }

    window.requestAnimationFrame(step);
}

function formatINR(num) {
    return "₹ " + Number(num || 0).toLocaleString("en-IN");
}

function loadSummary() {

    const filterEl = document.getElementById("filterType");

    // 🔥 Prevent crash if element not ready
    if (!filterEl) return;

    let filter = filterEl.value || "today";

    // 🔥 Safety override (fix bug)
    if (!["today", "week", "15days", "month", "custom", "3months", "year"].includes(filter)) {
        filter = "today";
    }

    let url = `${API}/summary?filter=${filter}`;

    if (filter === "custom") {

        function formatDateToBackend(dateStr) {
            if (!dateStr) return "";
            if (dateStr.split("-")[0].length === 4) return dateStr;

            const parts = dateStr.split("-");
            return `${parts[2]}-${parts[1]}-${parts[0]}`;
        }

        const startEl = document.getElementById("startDate");
        const endEl = document.getElementById("endDate");

        const rawStart = startEl ? startEl.value : "";
        const rawEnd = endEl ? endEl.value : "";

        if (!rawStart && !rawEnd) return;

        const startRaw = rawStart || rawEnd;
        const endRaw = rawEnd || rawStart;

        const start = formatDateToBackend(startRaw);
        const end = formatDateToBackend(endRaw);

        url += `&start=${start}&end=${end}`;
    }

    fetch(url)
    .then(res => res.json())
    .then(data => {

        const box = document.getElementById("summaryBox");
        if (!box) return;

        const netClass =
            data.net > 0 ? "summary-profit" :
            data.net < 0 ? "summary-loss" :
            "summary-neutral";

        box.innerHTML = `
            <div class="summary-card summary-purchase">
            <span class="summary-icon">🛒</span>
            <h4>Purchase</h4>
            <p id="sumPurchase">0</p>
        </div>

        <div class="summary-card summary-payment">
            <span class="summary-icon">💰</span>
            <h4>Payment</h4>
            <p id="sumPayment">0</p>
        </div>

        <div class="summary-card summary-neutral">
            <span class="summary-icon">📊</span>
            <h4>Net (Period)</h4>
            <p id="sumNet">0</p>
        </div>

        <div class="summary-card summary-neutral">
            <span class="summary-icon">📈</span>
            <h4>Closing Balance</h4>
            <p id="sumClosing">0</p>
        </div>
    `; 

        animateValue("sumPurchase", 0, Number(data.total_purchase) || 0);
        animateValue("sumPayment", 0, Number(data.total_payment) || 0);
        animateValue("sumNet", 0, Number(data.net) || 0);
        animateValue("sumClosing", 0, Number(data.closing_balance) || 0);
    })
    
    .catch(err => {
        console.error("Summary error:", err);
    });
} 

function setCurrentDateTime() {

    const now = new Date();

    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    const hours = String(now.getHours()).padStart(2, '0');
    const minutes = String(now.getMinutes()).padStart(2, '0');

    document.getElementById("date").value =
        `${year}-${month}-${day}T${hours}:${minutes}`;
    }

window.onload = function() {
    setCurrentDateTime();
    loadEntries();
    loadTotalDashboard();
    const filterEl = document.getElementById("filterType");
    if (filterEl) filterEl.value = "week";

    loadSummary();
    
    updateActiveNav("topSection");

    const splash = document.getElementById("splashScreen");
    const logo = document.getElementById("splashLogo");
    const app = document.getElementById("appRoot");
    const main = document.querySelector(".main-content");
    const card = document.getElementById("splashCard");

    setTimeout(() => {

        /* STEP 1: shrink splash */
        if (card) card.classList.add("shrink-card");

        /* STEP 2: morph logo */
        if (logo) {
            const rect = logo.getBoundingClientRect();

            logo.classList.add("morph-logo");

            logo.style.top = rect.top + "px";
            logo.style.left = rect.left + "px";
            logo.style.width = rect.width + "px";

            setTimeout(() => {
                logo.style.top = "15px";
                logo.style.left = "20px";
                logo.style.width = "40px";
            }, 100);
        }

        /* STEP 3: show app */
        setTimeout(() => {
            if (app) {
                app.classList.remove("app-hidden");
                app.classList.add("app-visible");
            }

            if (main) {
                main.classList.add("loaded");
            }
        }, 400);

        /* STEP 4: remove splash */
        setTimeout(() => {
            if (splash) splash.remove();
        }, 1000);

    }, 1800);
    
    startAutoRefresh();
};   
addRippleEffect();

function downloadExcel() {
    window.location.href = "/export_excel";
}

function downloadBackup() {
    window.location.href = "/download_backup";
}

function searchCustomer() {
    const name = document.getElementById("searchName").value.trim();

    if (!name) {
        alert("Enter customer name");
        return;
    }

    fetch(`${API}/get_entries_by_name?name=${name}`)
    .then(res => res.json())
    .then(data => {
        const tbody = document.querySelector("#ledgerTable tbody");
        tbody.innerHTML = "";

        data.forEach(e => {
            const row = `
                <tr class="${e.balance > 0 ? 'row-neg' : e.balance < 0 ? 'row-pos' : 'row-zero'}">
                    <td>${e.date}</td>
                    <td>${e.name}</td>
                    <td>${e.previous}</td>
                    <td>${e.purchase}</td>
                    <td>${e.total}</td>
                    <td>${e.payment}</td>
                    <td class="${e.balance > 0 ? 'neg' : e.balance < 0 ? 'pos' : 'zero'}">
                        ${e.balance}
                        <div class="badge">
                            ${e.balance > 0 ? 'Due' : e.balance < 0 ? 'Advance' : 'Settled'}
                        </div>
                    </td>
                    <td>
                        <button onclick='editEntry(${JSON.stringify(e)})'>Edit</button>
                        <button onclick="deleteEntry(${e.id})" style="background:red;">Delete</button>
                    </td>
                </tr>
            `;
            tbody.innerHTML += row;
        });
    });
}

const searchInput = document.getElementById("searchName");

if (searchInput) {
    searchInput.addEventListener("input", function() {
        if (this.value.trim() === "") {
            loadEntries();
            loadSummary();
        }
    });
}

function toggleMenu() {
    const sidebar = document.getElementById("sidebar");
    sidebar.classList.toggle("active");
}

if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
        navigator.serviceWorker.register("/static/service-worker.js")
        .then(() => console.log("Service Worker Registered"))
        .catch(err => console.log("SW Error:", err));
    });
}

let deferredPrompt;

window.addEventListener("beforeinstallprompt", (e) => {
    e.preventDefault();
    deferredPrompt = e;

    const installBtn = document.getElementById("installBtn");
    if (installBtn) {
        installBtn.style.display = "block";

        installBtn.onclick = () => {
            installBtn.style.display = "none";
            deferredPrompt.prompt();

            deferredPrompt.userChoice.then(choiceResult => {
                if (choiceResult.outcome === "accepted") {
                    console.log("App installed");
                }
                deferredPrompt = null;
            });
        };
    }
});

function toggleTheme() {
    document.body.classList.toggle("dark");

    const btn = document.getElementById("themeToggle");

    if (document.body.classList.contains("dark")) {
        btn.innerText = "☀ Light";
        localStorage.setItem("theme", "dark");
    } else {
        btn.innerText = "🌙 Dark";
        localStorage.setItem("theme", "light");
    }
}

function navigateTo(sectionId) {

    const screens = document.querySelectorAll(".screen");

    screens.forEach(screen => {
        screen.classList.remove("active");
        screen.classList.add("exit");
    });

    if (sectionId === "restoreSection") loadBackupList();
    if (sectionId === "expenseSection") loadExpenses();

    setTimeout(() => {

        screens.forEach(screen => {
            screen.classList.remove("exit");
        });

        const target = document.getElementById(sectionId);
        if (target) target.classList.add("active");

        // auto refresh data
        if (sectionId === "tableSection") loadEntries();
        if (sectionId === "summarySection") loadSummary();
        if (sectionId === "topSection") loadTotalDashboard();

        // highlight active nav
        updateActiveNav(sectionId);

    }, 200);
}

// Load saved theme
window.addEventListener("load", () => {
    const saved = localStorage.getItem("theme");
    if (saved === "dark") {
        document.body.classList.add("dark");
        const btn = document.getElementById("themeToggle");
        if (btn) btn.innerText = "☀ Light";
    }
});

window.addEventListener("load", () => {
    const sound = document.getElementById("startupSound");
    if (sound) {
        sound.volume = 0.2;
        sound.play().catch(() => {});
    }
});

function addRippleEffect() {
    const buttons = document.querySelectorAll("button");

    buttons.forEach(button => {
        button.classList.add("ripple");

        button.addEventListener("click", function (e) {
            const circle = document.createElement("span");
            const rect = button.getBoundingClientRect();

            circle.style.left = (e.clientX - rect.left) + "px";
            circle.style.top = (e.clientY - rect.top) + "px";

            button.appendChild(circle);

            setTimeout(() => circle.remove(), 600);
        });
    });
}

let startX = 0;
let endX = 0;

document.addEventListener("touchstart", e => {
    startX = e.touches[0].clientX;
});

document.addEventListener("touchend", e => {
    endX = e.changedTouches[0].clientX;
    handleSwipe();
});

function handleSwipe() {
    const diff = startX - endX;

    const order = ["topSection", "formSection", "tableSection", "summarySection"];
    const current = document.querySelector(".screen.active");

    if (!current) return;

    const index = order.indexOf(current.id);

    // swipe left → next
    if (diff > 50 && index < order.length - 1) {
        navigateTo(order[index + 1]);
    }

    // swipe right → previous
    if (diff < -50 && index > 0) {
        navigateTo(order[index - 1]);
    }
}

function updateActiveNav(sectionId) {
    document.querySelectorAll(".sidebar button").forEach(btn => {
        btn.classList.remove("active-nav");
    });

    const map = {
        topSection: 0,
        formSection: 1,
        tableSection: 2,
        summarySection: 3
    };

    const buttons = document.querySelectorAll(".sidebar button");

    if (buttons[map[sectionId]]) {
        buttons[map[sectionId]].classList.add("active-nav");
    }
}

const filterEl = document.getElementById("filterType");

if (filterEl) {
    filterEl.addEventListener("change", function () {

        const custom = document.getElementById("customRange");

        if (this.value === "custom") {
            custom.style.display = "block";
        } else {
            custom.style.display = "none";
        }
        
        loadSummary();
    });
}

function loadTotalDashboard() {
    fetch(`${API}/total_summary`)
    .then(res => res.json())
    .then(data => {

        // 🔥 Direct set FIRST (critical fix)
        document.getElementById("cardPurchase").innerText = data.total_purchase;
        document.getElementById("cardPayment").innerText = data.total_payment;
        document.getElementById("cardNet").innerText = data.net;

        // Optional animation AFTER render (safe)
        animateValue("cardPurchase", 0, data.total_purchase);
        animateValue("cardPayment", 0, data.total_payment);
        animateValue("cardNet", 0, data.net);

        const netCard = document.getElementById("netCard");
        const netStatus = document.getElementById("netStatus");

        if (data.net < 0) {
            netCard.style.background = "#dc3545";
            netStatus.innerText = "↓ Loss";
        } else if (data.net > 0) {
            netCard.style.background = "#16a34a";
            netStatus.innerText = "↑ Profit";
        } else {
            netCard.style.background = "#6c757d";
            netStatus.innerText = "Balanced";
        }
    });
}

function loadBackupList() {
    fetch(`${API}/list_backups`)
    .then(res => res.json())
    .then(files => {

        const container = document.getElementById("backupList");
        if (!container) return;

        container.innerHTML = "";

        files.forEach(file => {
            const row = document.createElement("div");
            row.style.marginBottom = "8px";

            row.innerHTML = `
                <span>${file}</span>
                <button onclick="restoreBackup('${file}')" style="margin-left:10px;background:#dc3545;">
                    Restore
                </button>
            `;

            container.appendChild(row);
        });
    });
}

function restoreBackup(filename) {
    if (!confirm("Restore this backup? Current data will be replaced!")) return;

    fetch(`${API}/restore_backup`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ filename })
    })
    .then(res => res.json())
    .then(data => {
        alert(data.message || data.error);

        // reload everything
        loadEntries();
    
        setTimeout(() => {
            loadSummary();
            loadTotalDashboard();
        }, 300);
    });
}

function addExpense() {
    const title = document.getElementById("expTitle").value.trim();
    const amount = document.getElementById("expAmount").value;
    const date = document.getElementById("expDate").value;

    if (!title || amount <= 0) {
        alert("Enter valid expense");
        return;
    }

    fetch(`${API}/add_expense`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, amount, date })
    })
    .then(res => res.json())
    .then(() => {
        loadExpenses();

        setTimeout(() => {
            loadSummary();
            loadTotalDashboard();
        }, 300);

        document.getElementById("expTitle").value = "";
        document.getElementById("expAmount").value = "";
    });
}

function loadExpenses() {
    fetch(`${API}/get_expenses`)
    .then(res => res.json())
    .then(data => {
        const tbody = document.getElementById("expenseTable");
        if (!tbody) return;

        tbody.innerHTML = "";

        data.forEach(e => {
            tbody.innerHTML += `
                <tr>
                    <td>${e.date}</td>
                    <td>${e.title}</td>
                    <td>₹ ${e.amount}</td>
                    <td>
                        <button onclick="deleteExpense(${e.id})" style="background:red;">
                            Delete
                        </button>
                    </td>
                </tr>
            `;
        });
    });
}

function deleteExpense(id) {
    if (!confirm("Delete expense?")) return;

    fetch(`${API}/delete_expense/${id}`, {
        method: 'DELETE'
    })

    .then(() => {
        loadExpenses();

        setTimeout(() => {
            loadSummary();
            loadTotalDashboard();
        }, 300);
    });
}

// ✅ AUTO REFRESH SYSTEM (SAFE)
function startAutoRefresh() {

    // Prevent duplicate intervals
    if (window.autoRefreshInterval) return;

    window.autoRefreshInterval = setInterval(() => {

        const activeScreen = document.querySelector(".screen.active");

        if (!activeScreen) return;

        const id = activeScreen.id;

        // Only refresh visible screen (optimized)
        if (id === "tableSection") {
            loadEntries();
        }

        if (id === "summarySection") {
            loadSummary();
        }

        if (id === "topSection") {
            loadTotalDashboard();
        }

    }, 5000); // every 5 seconds
}

function showSuccessPopup() {

    const popup = document.getElementById("successPopup");
    if (!popup) return;

    popup.style.display = "block";

    setTimeout(() => {
        popup.style.display = "none";
    }, 2000);
}

function uploadToDrive() {

    if (!confirm("Upload latest backup to Google Drive?")) return;

    fetch(`${API}/upload_to_drive`)
    .then(res => res.json())
    .then(data => {

        if (data.message) {
            alert(data.message);   // success
        } else {
            alert(data.error || "Upload failed");
        }

    })
    .catch(() => {
        alert("Request failed");
    });
}

function sendWhatsApp(name, balance, phone) {

    if (!phone) {
        alert("Phone number not available");
        return;
    }

    if (balance <= 0) {
        alert("No due for this customer");
        return;
    }

    const message = `This is regarding my outstanding balance of ₹${balance}. I will be clearing part of my outstanding shortly and Remaining will be settled soon. Thank you. - MM LifeCare Medical`;

    const encoded = encodeURIComponent(message);

    const cleanPhone = phone.replace(/\D/g, "");
    const url = `https://wa.me/91${cleanPhone}?text=${encoded}`;

    window.open(url, "_blank");
}

function sendBulkReminder() {
    fetch(`${API}/get_customers_summary`)
    .then(res => res.json())
    .then(data => {

        const dueCustomers = data.filter(c => c.balance > 0 && c.phone);

        if (!dueCustomers.length) {
            alert("No due customers with phone numbers");
            return;
        }

        dueCustomers.forEach(e => {
            const msg = `This is regarding my outstanding balance of ₹${e.balance}. I will be clearing part of my outstanding shortly and Remaining will be settled soon. Thank you. - MM LifeCare Medical`;

            const cleanPhone = e.phone.replace(/\D/g, "");
            const url = `https://wa.me/91${cleanPhone}?text=${encodeURIComponent(msg)}`;

            window.open(url, "_blank");
        });
    });
}

function loadCustomerSummary() {
    fetch(`${API}/get_customers_summary`)
    .then(res => res.json())
    .then(data => {
        let table = document.getElementById("customerTableBody"); // ✅ FIX
        table.innerHTML = "";

        data.forEach(c => {
            let due = c.balance > 0 ? `<span style="color:red">${c.balance} Due</span>` : c.balance;

            table.innerHTML += `
                <tr>
                    <td>${c.name}</td>
                    <td>${c.phone || '-'}</td>
                    <td>${due}</td>
                    <td>
                        <button onclick="viewCustomer('${c.name}')">View</button>
                        <button onclick="sendWhatsAppCustomer('${c.phone}', '${c.name}', ${c.balance})">
                            WhatsApp
                        </button>
                    </td>
                </tr>
            `;
        });
    });
}

function viewCustomer(name) {

    navigateTo('tableSection');  // keep this

    fetch(`${API}/get_entries`)
    .then(res => res.json())
    .then(data => {

        let filtered = data.filter(e => e.name === name);

        const tbody = document.getElementById("ledgerTableBody");
        tbody.innerHTML = "";

        if (!filtered.length) {
            tbody.innerHTML = "<tr><td colspan='10'>No data</td></tr>";
            return;
        }

        filtered.forEach(e => {
            const row = `
                <tr>
                    <td>${e.date}</td>
                    <td>${e.name}</td>
                    <td>${e.phone || '-'}</td>
                    <td>${e.previous}</td>
                    <td>${e.purchase}</td>
                    <td>${e.total}</td>
                    <td>${e.payment}</td>
                    <td>${e.balance}</td>

                    <!-- Action column -->
                    <td>
                        <button onclick='editEntry(${JSON.stringify(e)})'>Edit</button>
                        <button onclick="deleteEntry(${e.id})" style="background:red;">
                            Delete
                        </button>
                    </td>

                    <!-- Reminder column -->
                    <td>
                        <button onclick="sendWhatsApp('${e.name}', ${e.balance}, '${e.phone || ""}')" 
                                style="background:#25D366;">
                            WhatsApp
                        </button>
                    </td>
                </tr>
            `;
            tbody.innerHTML += row;
        });
    });
}

function sendWhatsAppCustomer(phone, name, balance) {
    if (!phone) {
        alert(`No phone for ${name}`);
        return;
    }

    let msg = `Dear ${name}, this is regarding my outstanding balance of ₹${balance}. I will be clearing part of my outstanding shortly and Remaining will be settled soon. Thank you. - MM LifeCare Medical`;

    let url = `https://wa.me/91${phone}?text=${encodeURIComponent(msg)}`;
    window.open(url, '_blank');
}

function sendSMS(name, balance, phone) {

    if (!phone) {
        alert("Phone number not available");
        return;
    }

    const message = `This is regarding my outstanding balance of ₹${balance}. I will be clearing part of my outstanding shortly and Remaining will be settled soon. Thank you. - MM LifeCare Medical`;

    fetch(`${API}/send_sms`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone, message })
    })
    .then(res => res.json())
    .then(data => {
        console.log("SMS RESPONSE:", data);

        if (data.success) {
            alert("SMS sent successfully");
        } else {
            alert("SMS failed: " + JSON.stringify(data));
        }
    })
    .catch(err => {
        console.error(err);
        alert("SMS request error");
    });
}

function sendBulkSMS() {
    fetch(`${API}/get_customers_summary`)
    .then(res => res.json())
    .then(data => {

        const due = data.filter(c => c.balance > 0 && c.phone);

        due.forEach(c => {
            const message = `This is regarding my outstanding balance of ₹${c.balance}. I will clear it soon. - MM LifeCare Medical`;

            fetch(`${API}/send_sms`), {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({ phone: c.phone, message })
            });
        });

        alert("Bulk SMS sent");
    });
}