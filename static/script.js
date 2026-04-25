const API = window.location.origin;

// NAVIGATION
function navigateTo(sectionId) {
    const screens = document.querySelectorAll(".screen");
    screens.forEach(s => {
        s.classList.remove("active");
        s.style.display = "none";
    });

    const target = document.getElementById(sectionId);
    if (!target) return;

    target.classList.add("active");
    target.style.display = "block";

    if (sectionId === "tableSection") loadEntries();
    if (sectionId === "topSection") {
        loadDashboard();
        updateDashboardLabels(document.getElementById("entryType").value);
    }
    if (sectionId === "summarySection") loadSummary();
    if (sectionId === "expenseSection") {
        loadExpenses();
        loadExpenseSummary();
        loadExpenseBreakdown();
    }
}

// DOM READY
document.addEventListener("DOMContentLoaded", function () {

    const entryType = document.getElementById("entryType");

    // AUTO DATE FIX
    const now = new Date();
    const formatted = now.toISOString().slice(0,16);

    // Ledger date (already exists)
    const ledgerDate = document.getElementById("date");
    if (ledgerDate) {
        ledgerDate.value = formatted;
    }

    // Expense date (new field)
    const expDate = document.getElementById("expDate");
    if (expDate && !expDate.value) {
        expDate.value = new Date().toISOString().slice(0,16);
    }

    const startField = document.getElementById("rangeStart");
    const endField = document.getElementById("rangeEnd");

    if (startField && endField) {
        const today = now.toISOString().slice(0,16);
        startField.value = today;
        endField.value = today;
    }

    entryType.addEventListener("change", function () {
        updateDashboardLabels(this.value);
        loadDashboard();
        loadEntries();
        loadSummary();
    });

    navigateTo("topSection");

    const btn = document.getElementById("themeBtn");

    if (btn) {
        btn.addEventListener("click", toggleTheme);
    }

    const savedTheme = localStorage.getItem("theme");
    const themeBtn = document.getElementById("themeBtn");

    if (savedTheme === "dark") {
        document.body.classList.add("dark-theme");
        if (themeBtn) themeBtn.innerText = "☀️ Light Mode";
     } else {
        if (themeBtn) themeBtn.innerText = "🌙 Dark Mode";
    }

});

// DASHBOARD LABELS
function updateDashboardLabels(type) {
    if (type === "customer") {
        document.querySelector(".card.blue h4").innerText = "Total Sale";
        document.querySelector(".card.green h4").innerText = "Total Received";
        document.querySelector(".card.yellow h4").innerText = "Customer Due";
    } else {
        document.querySelector(".card.blue h4").innerText = "Total Purchase";
        document.querySelector(".card.green h4").innerText = "Total Paid";
        document.querySelector(".card.yellow h4").innerText = "Supplier Due";
    }
}

// DASHBOARD
function loadDashboard() {
    const type = document.getElementById("entryType").value;

    fetch(`${API}/total_summary?type=${type}`)
        .then(res => res.json())
        .then(data => {
            document.getElementById("cardPurchase").innerText = data.total_purchase || 0;
            document.getElementById("cardPayment").innerText = data.total_payment || 0;
            document.getElementById("cardNet").innerText = data.net || 0;
        });
}

// ✅ FIXED ADD ENTRY (MAIN ISSUE)
function addEntry() {

    const type = document.getElementById("entryType").value;

    const payload = {
        type: type,
        customer_name: document.getElementById("name").value.trim(),
        phone: document.getElementById("phone").value.trim(),
        current_purchase: parseFloat(document.getElementById("purchase").value) || 0,
        payment: parseFloat(document.getElementById("payment").value) || 0,
        date: document.getElementById("date").value
    };

    // VALIDATION
    if (!payload.customer_name) {
        alert("Name is required");
        return;
    }

    fetch(`${API}/add_entry`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify(payload)
    })
    .then(res => res.json())
    .then(data => {

        if (data.error) {
            alert(data.error);
            return;
        }

        alert("Entry added successfully");

        // CLEAR FORM
        document.getElementById("name").value = "";
        document.getElementById("phone").value = "";
        document.getElementById("purchase").value = "";
        document.getElementById("payment").value = "";

        // RELOAD DATA
        loadEntries();
        loadDashboard();
    })
    .catch(err => {
        console.error(err);
        alert("Error adding entry");
    });
}

// LOAD LEDGER
function loadEntries() {
    const type = document.getElementById("entryType").value;

    fetch(`${API}/get_entries?type=${type}`)
        .then(res => res.json())
        .then(data => {
            const body = document.getElementById("ledgerTableBody");
            body.innerHTML = "";

            data.forEach(e => {
                body.innerHTML += `
                <tr>
                    <td>${e.date}</td>
                    <td>${e.name}</td>
                    <td>${e.previous}</td>
                    <td>${e.purchase}</td>
                    <td>${e.payment}</td>
                    <td>${e.balance}</td>
                    <td>
                        <button onclick="editEntry(${e.id}, '${e.name}', ${e.purchase}, ${e.payment}, '${e.phone || ""}')">Edit</button>
                        <button onclick="deleteEntry(${e.id})">Delete</button>
                        <button onclick="sendWhatsApp('${e.name}', ${e.balance}, '${e.phone || ""}')">WhatsApp</button>
                    </td>
                </tr>`;
            });
        });
}

// EDIT
function editEntry(id, name, purchase, payment, phone) {
    const n = prompt("Name:", name);
    if (n === null) return;

    fetch(`${API}/update_entry/${id}`, {
        method: "PUT",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
            customer_name: n,
            current_purchase: parseFloat(prompt("Amount:", purchase)) || 0,
            payment: parseFloat(prompt("Payment:", payment)) || 0,
            phone: prompt("Phone:", phone)
        })
    }).then(() => loadEntries());
}

// DELETE
function deleteEntry(id) {
    if (!confirm("Delete this entry?")) return;

    fetch(`${API}/delete_entry/${id}`, { method: "DELETE" })
        .then(() => loadEntries());
}

// WHATSAPP
function sendWhatsApp(name, balance, phone) {
    if (!phone || balance <= 0) return;

    const clean = phone.replace(/\D/g, "");
    const msg = `Dear ${name}, Your due is ₹${balance}`;

    window.open(`https://wa.me/${clean}?text=${encodeURIComponent(msg)}`);
}

// EXPENSE
function addExpense() {
    fetch(`${API}/add_expense`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
            title: document.getElementById("expTitle").value,
            category: document.getElementById("expCategory").value,
            amount: document.getElementById("expAmount").value,
            date: document.getElementById("expDate").value
        })
    }).then(loadExpenses);
}

function loadExpenses() {
    fetch(`${API}/get_expenses`)
        .then(res => res.json())
        .then(data => {
            const table = document.getElementById("expenseTable");
            table.innerHTML = "";

            data.forEach(e => {
                table.innerHTML += `<tr><td>${e.date}</td><td>${e.title}</td><td>${e.amount}</td></tr>`;
            });
        });
}

function loadExpenseBreakdown() {

    const period = document.getElementById("expensePeriod").value;

    fetch(`${API}/expense_breakdown?period=${period}`)
    .then(res => res.json())
    .then(data => {

        let html = `<b>Total (${data.period}): ₹${data.total}</b><br><br>`;

        for (let cat in data.categories) {
            html += `${cat.toUpperCase()}: ₹${data.categories[cat]}<br>`;
        }

        document.getElementById("expenseBreakdown").innerHTML = html;
    });
}

function loadExpenseSummary() {

    const period = document.getElementById("expenseFilter").value;

    fetch(`${API}/expense_summary?period=${period}`)
    .then(res => res.json())
    .then(data => {

        document.getElementById("expenseSummary").innerHTML =
            `Total (${data.period}): ₹${data.total} | Entries: ${data.count}`;
    });
}

function loadSummary() {

    const type = document.getElementById("entryType").value;

    fetch(`${API}/summary?type=${type}`)
    .then(res => res.json())
    .then(data => {

        document.getElementById("summaryBox").innerHTML = `
            <b>Total:</b> ₹${data.total_purchase}<br>
            <b>Received:</b> ₹${data.total_payment}<br>
            <b>Net:</b> ₹${data.net}<br>
            <b>Closing Balance:</b> ₹${data.closing_balance}
        `;
    });
}

function loadExpenseRange() {

    const start = document.getElementById("rangeStart").value;
    const end = document.getElementById("rangeEnd").value;

    if (!start || !end) {
        alert("Select both start and end date");
        return;
    }

    fetch(`${API}/expenses_by_range?start=${start}&end=${end}`)
    .then(res => res.json())
    .then(data => {

        let html = `<b>Total: ₹${data.total} | Entries: ${data.count}</b><br><br>`;

        data.data.forEach(e => {
            html += `${e.date} | ${e.title} | ₹${e.amount} (${e.category})<br>`;
        });

        document.getElementById("rangeResult").innerHTML = html;
    });
}

function toggleTheme() {

    document.body.classList.toggle("dark-theme");

    const isDark = document.body.classList.contains("dark-theme");

    // Save preference
    localStorage.setItem("theme", isDark ? "dark" : "light");

    // Update button text
    const btn = document.getElementById("themeBtn");
    if (btn) {
        btn.innerText = isDark ? "☀️ Light Mode" : "🌙 Dark Mode";
    }
}

if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("/static/sw.js")
        .then(() => console.log("Service Worker Registered"));
}