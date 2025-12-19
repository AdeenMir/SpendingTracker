# 🏦 Spending Tracker App

A beautiful, modern Flutter app for tracking your personal finances with Firebase backend.

## 🚨 READ THIS FIRST

**Your app is not showing data?** 

👉 **SEE: [CRITICAL_FIX.md](CRITICAL_FIX.md)** - 3-step fix for 99% of issues

---

## ✨ Features

- 💰 **Track Transactions** - Add income, expenses, and loans
- 🎯 **Multiple Accounts** - Create and manage different accounts
- 📊 **Analytics** - View spending breakdown by category
- 🌙 **Dark Mode** - Light, Dark, or System theme
- 💱 **Multi-Currency** - Support for 6 currencies (Rs, $, €, £, ¥, CHF)
- 🔐 **Secure** - Firebase authentication and Firestore backend
- 📱 **Modern UI** - Beautiful Material Design 3 interface

---

## 🔧 Quick Start

### Prerequisites
- Flutter 3.9.2+
- Firebase project setup
- Valid Firestore instance

### Installation
```bash
# Get dependencies
flutter pub get

# Run the app
flutter run
```

### First Time Setup
1. **Update Firestore Rules** → See [CRITICAL_FIX.md](CRITICAL_FIX.md)
2. **Login** with your Firebase email
3. **Add a transaction** with the + button
4. **Enjoy!**

---

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| [CRITICAL_FIX.md](CRITICAL_FIX.md) | 🚨 **Start here if nothing shows** |
| [FIRESTORE_RULES.md](FIRESTORE_RULES.md) | Security rules to copy into Firebase |
| [SETUP_GUIDE.md](SETUP_GUIDE.md) | Complete setup and troubleshooting |
| [EXPECTED_BEHAVIOR.md](EXPECTED_BEHAVIOR.md) | What the app should look like |

---

## 🎮 How to Use

### Adding a Transaction
1. Click the **+** button (bottom right)
2. Select Type: Income, Expense, or Loan
3. Choose Category (auto-updates based on type)
4. Enter Amount
5. Add optional Note
6. Click "Save Transaction"

### Switching Accounts
1. Go to **Home** tab
2. Click **+** icon on the balance card
3. Enter account name
4. New account appears in the "Other Accounts" section

### Changing Theme
1. Go to **Settings** tab
2. Select: Light, Dark, or System
3. Change persists automatically

### Changing Currency
1. Go to **Settings** tab
2. Click on desired currency chip
3. All amounts update instantly

### Viewing Analytics
1. Go to **Analytics** tab
2. See total income and expense
3. See breakdown of spending by category
4. View percentage of budget per category

---

## 🏗️ Project Structure

```
lib/
├── main.dart (1225+ lines - all code)
│   ├── MyApp (Theme & Currency management)
│   ├── HomePage (Navigation container)
│   ├── Dashboard (Home screen with balance)
│   ├── AddTransaction (Transaction form)
│   ├── TransactionsPage (All transactions list)
│   ├── AnalyticsPage (Spending breakdown)
│   └── SettingsPage (Theme & Currency)
```

---

## 📦 Dependencies

```yaml
firebase_core: ^4.3.0         # Firebase initialization
firebase_auth: ^6.1.3         # User authentication
cloud_firestore: ^6.1.1       # Database
shared_preferences: ^2.2.2    # Local settings storage
fl_chart: ^1.1.1              # (Optional) for future charts
```

---

## 🔐 Security

- ✅ Firebase Authentication required
- ✅ Firestore security rules restrict user data
- ✅ Each user can only see their own data
- ✅ No passwords stored locally
- ✅ All data encrypted in Firestore

**Important:** See [FIRESTORE_RULES.md](FIRESTORE_RULES.md) to set up proper security rules.

---

## 🐛 Troubleshooting

### Issue: "Permission Denied" Error
**Solution:** See [CRITICAL_FIX.md](CRITICAL_FIX.md)

### Issue: Empty Home Screen
**Solution:** Firestore rules aren't set up. See [FIRESTORE_RULES.md](FIRESTORE_RULES.md)

### Issue: Transactions Don't Save
**Solution:** Check Firestore rules. Run `flutter clean && flutter pub get`

### Issue: App Crashes on Startup
**Solution:** 
```bash
flutter clean
flutter pub get
flutter run
```

---

## 🎨 UI Highlights

- **Gradient Cards** - Beautiful teal gradients for balance display
- **Color Coding** - Green for income, red for expense, orange for totals
- **Smooth Animations** - Transitions between screens
- **Responsive Design** - Works on phones and tablets
- **Dark Mode Support** - Full dark theme available

---

## 📝 Transaction Categories

### Income
- Salary, Freelance, Investment, Bonus, Gift, Other

### Expense
- Food, Transport, Rent, Utilities, Entertainment, Health, Shopping, Education, Insurance, Other

### Loans
- Lent (money you gave out), Borrowed (money you got)

---

## 🚀 Future Features (Coming Soon)

- [ ] Recurring transactions
- [ ] Budget limits by category
- [ ] Transaction export (CSV/PDF)
- [ ] Charts and visualizations
- [ ] Bill reminders
- [ ] Multi-user sharing
- [ ] Receipt photos
- [ ] Monthly reports

---

## 📞 Support

If you encounter issues:

1. **Check the error message** - It often tells you the exact problem
2. **Read [CRITICAL_FIX.md](CRITICAL_FIX.md)** - Solves 99% of issues
3. **Look in [SETUP_GUIDE.md](SETUP_GUIDE.md)** - Detailed troubleshooting
4. **Check Firebase Console** - Verify Firestore data exists

---

## 📄 License

This project is provided as-is for personal use.

---

## 💡 Tips

- 💾 **Data Backup:** Firebase Firestore auto-backs up your data
- 🔄 **Sync:** All changes sync in real-time across devices
- 📊 **Reports:** Analytics tab shows spending patterns
- 🎯 **Planning:** Use expense data to plan your budget

---

**Version:** 1.0
**Last Updated:** December 2025
**Status:** Fully Functional ✅

👉 **New User?** Start with [CRITICAL_FIX.md](CRITICAL_FIX.md)
