import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

final auth = FirebaseAuth.instance;
final db = FirebaseFirestore.instance;

/* ===================== APP ROOT ===================== */

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  String _currency = '₹';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedTheme = prefs.getString('theme') ?? 'light';
      _themeMode = savedTheme == 'dark' ? ThemeMode.dark : ThemeMode.light;
      _currency = prefs.getString('currency') ?? '₹';
    });
  }

  void _updateTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _themeMode = mode);
    await prefs.setString('theme', mode == ThemeMode.dark ? 'dark' : 'light');
  }

  void _updateCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _currency = currency);
    await prefs.setString('currency', currency);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spending Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: StreamBuilder<User?>(
        stream: auth.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData) {
            return HomePage(
              themeMode: _themeMode,
              onThemeChanged: _updateTheme,
              currency: _currency,
              onCurrencyChanged: _updateCurrency,
            );
          }
          return const AuthPage();
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: Colors.teal,
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: isDark ? Colors.grey.shade900 : Colors.teal,
        foregroundColor: Colors.white,
      ),
    );
  }
}

/* ===================== HOME PAGE ===================== */

class HomePage extends StatefulWidget {
  final ThemeMode themeMode;
  final Function(ThemeMode) onThemeChanged;
  final String currency;
  final Function(String) onCurrencyChanged;

  const HomePage({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.currency,
    required this.onCurrencyChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    ensureDefaultAccount();
  }

  Future<void> ensureDefaultAccount() async {
    final uid = auth.currentUser!.uid;
    final snap = await db
        .collection('accounts')
        .where('uid', isEqualTo: uid)
        .where('name', isEqualTo: 'Current')
        .get();

    if (snap.docs.isEmpty) {
      await db.collection('accounts').add({
        'uid': uid,
        'name': 'Current',
        'balance': 0.0,
        'color': 'teal',
      });
    }

    // Initialize user settings
    final userSettingsSnap = await db
        .collection('users')
        .where('uid', isEqualTo: uid)
        .get();

    if (userSettingsSnap.docs.isEmpty) {
      await db.collection('users').add({
        'uid': uid,
        'currency': '₹',
        'theme': 'light',
      });
    }
  }

  late final pages = [
    Dashboard(currency: widget.currency),
    TransactionsPage(currency: widget.currency),
    BudgetPage(currency: widget.currency),
    AnalyticsPage(currency: widget.currency),
    SettingsPage(
      currentTheme: widget.themeMode,
      onThemeChanged: widget.onThemeChanged,
      currentCurrency: widget.currency,
      onCurrencyChanged: widget.onCurrencyChanged,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Spending Tracker",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async => await auth.signOut(),
          )
        ],
      ),
      body: pages[index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.receipt), label: "Transactions"),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: "Budget"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Analytics"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
      floatingActionButton: index < 3
          ? FloatingActionButton(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddTransaction(currency: widget.currency),
                ),
              ),
            )
          : null,
    );
  }
}

/* ===================== DASHBOARD ===================== */

class Dashboard extends StatefulWidget {
  final String currency;

  const Dashboard({super.key, required this.currency});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String? _selectedAccountName;

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('accounts').where('uid', isEqualTo: uid).snapshots(),
      builder: (context, accSnap) {
        if (accSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (accSnap.hasError) {
          return Center(child: Text("Error: ${accSnap.error}"));
        }

        if (!accSnap.hasData || accSnap.data!.docs.isEmpty) {
          return const Center(child: Text("No accounts found"));
        }

        // Find selected account or default to Current/first
        final allAccounts = accSnap.data!.docs;
        QueryDocumentSnapshot selectedAccount = allAccounts.first;
        
        // If no account selected yet, try to find 'Current'
        if (_selectedAccountName == null) {
          for (var acc in allAccounts) {
            if (acc['name'] == 'Current') {
              selectedAccount = acc;
              _selectedAccountName = 'Current';
              break;
            }
          }
          if (_selectedAccountName == null) {
            _selectedAccountName = selectedAccount['name'] as String;
          }
        } else {
          // Find the selected account
          for (var acc in allAccounts) {
            if (acc['name'] == _selectedAccountName) {
              selectedAccount = acc;
              break;
            }
          }
        }

        final balance = (selectedAccount['balance'] as num).toDouble();
        final selectedName = selectedAccount['name'] as String;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Main balance card
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withAlpha(100),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  "Balance",
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(50),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    selectedName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "${widget.currency} ${balance.toStringAsFixed(2)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _showAddAccountDialog(context),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(50),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(Icons.add, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // All accounts section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Accounts",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  "${allAccounts.length} account${allAccounts.length != 1 ? 's' : ''}",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            ...allAccounts.map((acc) {
              final accBalance = (acc['balance'] as num).toDouble();
              final accName = acc['name'] as String;
              final isSelected = accName == _selectedAccountName;
              
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedAccountName = accName;
                  });
                },
                onLongPress: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text(accName),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            'Balance',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.currency} ${accBalance.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: accBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (allAccounts.length > 1)
                            ElevatedButton.icon(
                              onPressed: () async {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    title: const Text('Delete Account'),
                                    content: Text('Delete \"$accName\" account?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () async {
                                          await acc.reference.delete();
                                          if (context.mounted) {
                                            if (_selectedAccountName == accName) {
                                              setState(() => _selectedAccountName = null);
                                            }
                                            Navigator.pop(context);
                                            Navigator.pop(ctx);
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                        ),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Delete Account'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.deepPurple : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Card(
                    elevation: isSelected ? 8 : 2,
                    margin: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: isSelected
                            ? LinearGradient(
                                colors: [
                                  Colors.deepPurple.withAlpha(30),
                                  Colors.deepPurple.withAlpha(10),
                                ],
                              )
                            : null,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? Colors.deepPurple.shade100
                              : Colors.teal.shade100,
                          child: Icon(
                            Icons.account_balance_wallet,
                            color: isSelected
                                ? Colors.deepPurple.shade700
                                : Colors.teal.shade700,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              accName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.deepPurple : null,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Selected',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          'Tap to view \u2022 Long press for options',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Text(
                          '${widget.currency} ${accBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: accBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // Quick stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: "Lent",
                    uid: uid,
                    loanType: 'lent',
                    currency: widget.currency,
                    color: Colors.blue,
                    icon: Icons.call_made,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: "Borrowed",
                    uid: uid,
                    loanType: 'borrowed',
                    currency: widget.currency,
                    color: Colors.orange,
                    icon: Icons.call_received,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Recent transactions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Recent Transactions",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text("View All"),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildRecentTransactions(uid, widget.currency, context),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String uid,
    required String loanType,
    required String currency,
    required Color color,
    required IconData icon,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('transactions')
          .where('uid', isEqualTo: uid)
          .where('type', isEqualTo: 'loan')
          .where('loanType', isEqualTo: loanType)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        double total = 0;
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            total += (doc['amount'] as num).toDouble();
          }
        }

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  color.withAlpha(50),
                  color.withAlpha(20),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: color.withAlpha(100),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  "$currency ${total.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentTransactions(String uid, String currency, BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('transactions')
          .where('uid', isEqualTo: uid)
          .orderBy('date', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, txSnap) {
        if (txSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (txSnap.hasError) {
          return Center(child: Text("Error: ${txSnap.error}"));
        }

        if (!txSnap.hasData || txSnap.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text("No transactions yet", style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ),
          );
        }

        return Column(
          children: txSnap.data!.docs.map((doc) {
            final type = doc['type'] as String;
            final amount = (doc['amount'] as num).toDouble();
            
            IconData icon;
            Color color;
            String prefix;
            
            if (type == 'loan') {
              final loanType = doc['loanType'] as String?;
              final status = doc['status'] as String? ?? 'pending';
              
              if (loanType == 'lent') {
                icon = Icons.call_made;
                color = status == 'settled' ? Colors.grey : Colors.blue.shade700;
                prefix = '';
              } else {
                icon = Icons.call_received;
                color = status == 'settled' ? Colors.grey : Colors.orange.shade700;
                prefix = '';
              }
            } else {
              final isIncome = type == 'income';
              icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
              color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
              prefix = isIncome ? '+' : '-';
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  decoration: BoxDecoration(
                    color: color.withAlpha(40),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, color: color),
                ),
                title: Text(doc['category'] ?? doc['person'] ?? 'Other'),
                subtitle: Text(_getTransactionSubtitle(doc)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "$prefix$currency ${amount.toStringAsFixed(2)}",
                      style: TextStyle(fontWeight: FontWeight.bold, color: color),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editTransaction(context, doc);
                        } else if (value == 'delete') {
                          _deleteTransaction(context, doc);
                        } else if (value == 'collect' || value == 'settle') {
                          _settleLoan(context, doc);
                        }
                      },
                      itemBuilder: (context) {
                        List<PopupMenuEntry<String>> items = [];
                        
                        if (type == 'loan') {
                          final status = doc['status'] as String? ?? 'pending';
                          final loanType = doc['loanType'] as String?;
                          if (status == 'pending') {
                            items.add(PopupMenuItem(
                              value: loanType == 'lent' ? 'collect' : 'settle',
                              child: Text(loanType == 'lent' ? 'Collect' : 'Settle'),
                            ));
                          }
                        }
                        
                        items.addAll([
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ]);
                        
                        return items;
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _getTransactionSubtitle(QueryDocumentSnapshot doc) {
    final type = doc['type'] as String;
    if (type == 'loan') {
      final loanType = doc['loanType'] as String?;
      final status = doc['status'] as String? ?? 'pending';
      return "${loanType ?? 'Loan'} - ${status.toUpperCase()}";
    }
    return type;
  }

  void _editTransaction(BuildContext context, QueryDocumentSnapshot doc) {
    final amountController = TextEditingController(text: doc['amount'].toString());
    
    // Safely get category or person
    String categoryText = '';
    try {
      categoryText = (doc['category'] as String?) ?? '';
    } catch (e) {
      // category doesn't exist, try person
      try {
        categoryText = (doc['person'] as String?) ?? '';
      } catch (e) {
        categoryText = '';
      }
    }
    
    final categoryController = TextEditingController(text: categoryText);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Edit Transaction"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: "Category/Person"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAmount = double.tryParse(amountController.text);
              if (newAmount != null && newAmount > 0) {
                try {
                  final oldAmount = (doc['amount'] as num).toDouble();
                  final diff = newAmount - oldAmount;
                  final type = doc['type'] as String;
                  final accountName = (doc['account'] as String?) ?? 'Current';
                  
                  // Build update map dynamically
                  final Map<String, dynamic> updateMap = {'amount': newAmount};
                  
                  // Get the data as a map to check which fields exist
                  final docData = doc.data() as Map<String, dynamic>;
                  
                  if (docData.containsKey('category')) {
                    updateMap['category'] = categoryController.text.trim();
                  } else if (docData.containsKey('person')) {
                    updateMap['person'] = categoryController.text.trim();
                  }
                  
                  // Update transaction
                  await doc.reference.update(updateMap);

                  // Update account balance using the correct account
                  if (type != 'loan' || (doc['status'] as String?) == 'settled') {
                    final uid = auth.currentUser!.uid;
                    final accQuery = await db
                        .collection('accounts')
                        .where('uid', isEqualTo: uid)
                        .where('name', isEqualTo: accountName)
                        .get();
                    
                    if (accQuery.docs.isNotEmpty) {
                      final accRef = accQuery.docs.first.reference;
                      final currentBalance = (accQuery.docs.first['balance'] as num).toDouble();
                      final multiplier = type == 'income' ? 1 : -1;
                      await accRef.update({'balance': currentBalance + (diff * multiplier)});
                    }
                  }

                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Transaction updated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _deleteTransaction(BuildContext context, QueryDocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Transaction"),
        content: const Text("Are you sure you want to delete this transaction?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final type = doc['type'] as String;
              final amount = (doc['amount'] as num).toDouble();
              
              // Reverse balance change if transaction was settled
              if (type != 'loan' || (doc['status'] as String?) == 'settled') {
                final uid = auth.currentUser!.uid;
                final accQuery = await db
                    .collection('accounts')
                    .where('uid', isEqualTo: uid)
                    .where('name', isEqualTo: 'Current')
                    .get();
                
                if (accQuery.docs.isNotEmpty) {
                  final accRef = accQuery.docs.first.reference;
                  final currentBalance = (accQuery.docs.first['balance'] as num).toDouble();
                  final multiplier = type == 'income' ? -1 : 1;
                  await accRef.update({'balance': currentBalance + (amount * multiplier)});
                }
              }

              await doc.reference.delete();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _settleLoan(BuildContext context, QueryDocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(doc['loanType'] == 'lent' ? 'Collect Loan' : 'Settle Loan'),
        content: Text("Mark this loan as ${doc['loanType'] == 'lent' ? 'collected' : 'settled'}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = (doc['amount'] as num).toDouble();
              final loanType = doc['loanType'] as String;
              
              // Update transaction status
              await doc.reference.update({'status': 'settled'});
              
              // Update account balance
              final uid = auth.currentUser!.uid;
              final accQuery = await db
                  .collection('accounts')
                  .where('uid', isEqualTo: uid)
                  .where('name', isEqualTo: 'Current')
                  .get();
              
              if (accQuery.docs.isNotEmpty) {
                final accRef = accQuery.docs.first.reference;
                final currentBalance = (accQuery.docs.first['balance'] as num).toDouble();
                final newBalance = loanType == 'lent' 
                    ? currentBalance + amount 
                    : currentBalance - amount;
                await accRef.update({'balance': newBalance});
              }

              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Confirm"),
          ),
        ],
      ),
    );
  }

  void _showAddAccountDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Account"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Account Name",
            prefixIcon: Icon(Icons.account_balance_wallet),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await db.collection('accounts').add({
                  'uid': auth.currentUser!.uid,
                  'name': controller.text.trim(),
                  'balance': 0.0,
                  'color': 'teal',
                });
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}

/* ===================== ADD TRANSACTION ===================== */

class AddTransaction extends StatefulWidget {
  final String currency;

  const AddTransaction({super.key, required this.currency});

  @override
  State<AddTransaction> createState() => _AddTransactionState();
}

class _AddTransactionState extends State<AddTransaction> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _personController = TextEditingController();

  String _type = 'expense';
  String _category = 'Food';
  String _loanType = 'lent';
  String? _selectedAccount;

  final List<String> _expenseCategories = [
    'Food', 'Transport', 'Rent', 'Utilities', 'Entertainment',
    'Health', 'Shopping', 'Education', 'Insurance', 'Other'
  ];

  final List<String> _incomeCategories = [
    'Salary', 'Freelance', 'Investment', 'Bonus', 'Gift', 'Other'
  ];

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Add Transaction"),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('accounts').where('uid', isEqualTo: uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No accounts found'));
          }

          final accounts = snapshot.data!.docs;
          _selectedAccount ??= accounts.first['name'] as String;

          final categories = _type == 'income' ? _incomeCategories : _expenseCategories;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Account dropdown
                DropdownButtonFormField<String>(
                  value: _selectedAccount,
                  decoration: InputDecoration(
                    labelText: 'Account',
                    prefixIcon: const Icon(Icons.account_balance_wallet),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: accounts.map((doc) {
                    final name = doc['name'] as String;
                    return DropdownMenuItem(value: name, child: Text(name));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedAccount = v),
                ),
                const SizedBox(height: 16),

                // Type dropdown
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: InputDecoration(
                    labelText: 'Type',
                    prefixIcon: const Icon(Icons.category),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'expense', child: Text('Expense')),
                    DropdownMenuItem(value: 'income', child: Text('Income')),
                    DropdownMenuItem(value: 'loan', child: Text('Loan')),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _type = v!;
                      if (_type != 'loan') {
                        _category = _type == 'income' ? _incomeCategories[0] : _expenseCategories[0];
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Category or Loan Type
                if (_type == 'loan') ...[
                  DropdownButtonFormField<String>(
                    value: _loanType,
                    decoration: InputDecoration(
                      labelText: 'Loan Type',
                      prefixIcon: const Icon(Icons.sync_alt),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'lent', child: Text('Lent (I gave)')),
                      DropdownMenuItem(value: 'borrowed', child: Text('Borrowed (I received)')),
                    ],
                    onChanged: (v) => setState(() => _loanType = v!),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _personController,
                    decoration: InputDecoration(
                      labelText: 'Person Name',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ] else
                  DropdownButtonFormField<String>(
                    value: _category,
                    decoration: InputDecoration(
                      labelText: 'Category',
                      prefixIcon: const Icon(Icons.label),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: categories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat));
                    }).toList(),
                    onChanged: (v) => setState(() => _category = v!),
                  ),
                const SizedBox(height: 16),

                // Amount
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: const Icon(Icons.attach_money),
                    prefixText: '${widget.currency} ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Note
                TextField(
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Note (optional)',
                    prefixIcon: const Icon(Icons.note),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveTransaction(uid, accounts),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Save Transaction', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveTransaction(String uid, List<QueryDocumentSnapshot> accounts) async {
    final amount = double.tryParse(_amountController.text);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    if (_type == 'loan' && _personController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter person name')),
      );
      return;
    }

    try {
      // Update account balance
      final accountDoc = accounts.firstWhere((doc) => doc['name'] == _selectedAccount);
      final currentBalance = (accountDoc['balance'] as num).toDouble();

      if (_type == 'income') {
        await accountDoc.reference.update({'balance': currentBalance + amount});
      } else if (_type == 'expense') {
        await accountDoc.reference.update({'balance': currentBalance - amount});
      }

      // Add transaction
      await db.collection('transactions').add({
        'uid': uid,
        'amount': amount,
        'type': _type,
        'category': _type == 'loan' ? null : _category,
        'person': _type == 'loan' ? _personController.text.trim() : null,
        'loanType': _type == 'loan' ? _loanType : null,
        'status': _type == 'loan' ? 'pending' : null,
        'date': Timestamp.now(),
        'note': _noteController.text.trim(),
        'account': _selectedAccount,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _personController.dispose();
    super.dispose();
  }
}

/* ===================== TRANSACTIONS PAGE ===================== */

class TransactionsPage extends StatefulWidget {
  final String currency;

  const TransactionsPage({super.key, required this.currency});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  String searchQuery = '';
  String filterType = 'all'; // all, income, expense, loan
  String sortBy = 'date'; // date, amount

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search and Filter Bar
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.withAlpha(30),
                Colors.deepPurple.withAlpha(12),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurple.withAlpha(40),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  prefixIcon: const Icon(Icons.search, color: Colors.deepPurple),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.deepPurple.shade100),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.deepPurple.shade100),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.deepPurple.shade300, width: 1.4),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                onChanged: (value) => setState(() => searchQuery = value),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: filterType,
                      style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Type',
                        hintText: 'Type',
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        prefixIcon: const Icon(Icons.filter_list, color: Colors.deepPurple),
                        labelStyle: TextStyle(color: Colors.grey.shade700),
                        hintStyle: TextStyle(color: Colors.grey.shade700),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.deepPurple.shade100),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.deepPurple.shade100),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.deepPurple.shade300, width: 1.4),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'income', child: Text('Income')),
                        DropdownMenuItem(value: 'expense', child: Text('Expense')),
                        DropdownMenuItem(value: 'loan', child: Text('Loans')),
                      ],
                      onChanged: (v) => setState(() => filterType = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: sortBy,
                      style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Sort',
                        hintText: 'Sort',
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        prefixIcon: const Icon(Icons.sort, color: Colors.deepPurple),
                        labelStyle: TextStyle(color: Colors.grey.shade700),
                        hintStyle: TextStyle(color: Colors.grey.shade700),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.deepPurple.shade100),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.deepPurple.shade100),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.deepPurple.shade300, width: 1.4),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'date', child: Text('Date')),
                        DropdownMenuItem(value: 'amount', child: Text('Amount')),
                      ],
                      onChanged: (v) => setState(() => sortBy = v!),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Transactions List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('transactions')
                .where('uid', isEqualTo: auth.currentUser!.uid)
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        "No transactions",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // Filter and search
              var docs = snapshot.data!.docs.where((doc) {
                final type = doc['type'] as String;
                final category = (doc['category'] ?? doc['person'] ?? '').toString().toLowerCase();
                final note = (doc['note'] ?? '').toString().toLowerCase();
                final query = searchQuery.toLowerCase();

                // Type filter
                if (filterType != 'all' && type != filterType) return false;

                // Search filter
                if (searchQuery.isNotEmpty) {
                  return category.contains(query) || note.contains(query);
                }

                return true;
              }).toList();

              // Sort
              if (sortBy == 'amount') {
                docs.sort((a, b) {
                  final amountA = (a['amount'] as num).toDouble();
                  final amountB = (b['amount'] as num).toDouble();
                  return amountB.compareTo(amountA);
                });
              }

              if (docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        "No matching transactions",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final type = doc['type'] as String;
                  final amount = (doc['amount'] as num).toDouble();
                  final date = (doc['date'] as Timestamp).toDate();

                  IconData icon;
                  Color color;
                  String prefix;
                  String title;

                  if (type == 'loan') {
                    final loanType = doc['loanType'] as String?;
                    final status = doc['status'] as String? ?? 'pending';
                    title = doc['person'] ?? 'Unknown';
                    
                    if (loanType == 'lent') {
                      icon = Icons.call_made;
                      color = status == 'settled' ? Colors.grey : Colors.blue.shade700;
                    } else {
                      icon = Icons.call_received;
                      color = status == 'settled' ? Colors.grey : Colors.orange.shade700;
                    }
                    prefix = '';
                  } else {
                    final isIncome = type == 'income';
                    title = doc['category'] ?? 'Other';
                    icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;
                    color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
                    prefix = isIncome ? '+' : '-';
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 2,
                    child: ListTile(
                      leading: Container(
                        decoration: BoxDecoration(
                          color: color.withAlpha(40),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Icon(icon, color: color),
                      ),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                      subtitle: Text(
                        '${type.toUpperCase()} • ${date.day}/${date.month}/${date.year}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                      trailing: Text(
                        "$prefix${widget.currency} ${amount.toStringAsFixed(2)}",
                        style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/* ===================== ANALYTICS PAGE ===================== */

class AnalyticsPage extends StatelessWidget {
  final String currency;

  const AnalyticsPage({super.key, required this.currency});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('transactions')
          .where('uid', isEqualTo: uid)
          .where('type', whereIn: ['income', 'expense'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.analytics_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  "No data to analyze",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
              ],
            ),
          );
        }

        // Calculate totals
        double totalIncome = 0;
        double totalExpense = 0;
        Map<String, double> expensesByCategory = {};

        for (var doc in snapshot.data!.docs) {
          final type = doc['type'] as String;
          final amount = (doc['amount'] as num).toDouble();

          if (type == 'income') {
            totalIncome += amount;
          } else if (type == 'expense') {
            totalExpense += amount;
            final category = doc['category'] as String? ?? 'Other';
            expensesByCategory[category] = (expensesByCategory[category] ?? 0) + amount;
          }
        }

        final balance = totalIncome - totalExpense;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildAnalyticsCard(
                    title: "Income",
                    amount: totalIncome,
                    currency: currency,
                    color: Colors.green,
                    icon: Icons.arrow_downward,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAnalyticsCard(
                    title: "Expense",
                    amount: totalExpense,
                    currency: currency,
                    color: Colors.red,
                    icon: Icons.arrow_upward,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildAnalyticsCard(
              title: "Net Balance",
              amount: balance,
              currency: currency,
              color: balance >= 0 ? Colors.teal : Colors.orange,
              icon: Icons.account_balance,
            ),

            const SizedBox(height: 24),

            // Visual Chart
            if (expensesByCategory.isNotEmpty) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Expense Distribution",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 200,
                        child: CustomPaint(
                          painter: PieChartPainter(
                            data: expensesByCategory,
                            total: totalExpense,
                          ),
                          child: Container(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: expensesByCategory.entries.map((entry) {
                          final color = _getCategoryColor(entry.key);
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                entry.key,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Expenses by Category
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Expenses by Category",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (expensesByCategory.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            "No expenses recorded",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )
                    else
                      ...expensesByCategory.entries.map((entry) {
                        final percentage = totalExpense > 0 
                            ? (entry.value / totalExpense * 100)
                            : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    "$currency ${entry.value.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: percentage / 100,
                                        backgroundColor: Colors.grey.shade200,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.red.shade400,
                                        ),
                                        minHeight: 8,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    "${percentage.toStringAsFixed(1)}%",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAnalyticsCard({
    required String title,
    required double amount,
    required String currency,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: color.withAlpha(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "$currency ${amount.toStringAsFixed(2)}",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ===================== SETTINGS PAGE ===================== */

class SettingsPage extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Function(String) onCurrencyChanged;
  final ThemeMode currentTheme;
  final String currentCurrency;

  const SettingsPage({
    super.key,
    required this.onThemeChanged,
    required this.onCurrencyChanged,
    required this.currentTheme,
    required this.currentCurrency,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _notifications = true;
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  String _name = "Your Name";
  String _address = "Your Address";

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addressController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notifications = prefs.getBool('notifications') ?? true;
      _name = prefs.getString('profile_name') ?? "Your Name";
      _address = prefs.getString('profile_address') ?? "Your Address";
    });
    _nameController.text = _name;
    _addressController.text = _address;
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final updatedName = _nameController.text.trim().isEmpty
        ? "Your Name"
        : _nameController.text.trim();
    final updatedAddress = _addressController.text.trim().isEmpty
        ? "Your Address"
        : _addressController.text.trim();

    await prefs.setString('profile_name', updatedName);
    await prefs.setString('profile_address', updatedAddress);

    if (!mounted) return;
    setState(() {
      _name = updatedName;
      _address = updatedAddress;
    });

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated')),
    );
  }

  void _openProfileSheet() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) {
          final email = auth.currentUser?.email ?? 'Not available';

          return Scaffold(
            backgroundColor: const Color(0xFF0F1116),
            appBar: AppBar(
              title: const Text('Edit Profile'),
              backgroundColor: const Color(0xFF161922),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1F1F2E),
                            const Color(0xFF141726),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(120),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                            ),
                            child: const Icon(Icons.account_circle, color: Colors.white, size: 34),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  email,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _address,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.75),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      color: const Color(0xFF161922),
                      elevation: 6,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Details',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _nameController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Full Name',
                                hintText: 'Enter your full name',
                                prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintStyle: const TextStyle(color: Colors.white60),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.deepPurple.shade200, width: 1.4),
                                ),
                                filled: true,
                                fillColor: const Color(0xFF1E2230),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _addressController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Address',
                                hintText: 'Street, City, Country',
                                prefixIcon: const Icon(Icons.home_outlined, color: Colors.white70),
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintStyle: const TextStyle(color: Colors.white60),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.deepPurple.shade200, width: 1.4),
                                ),
                                filled: true,
                                fillColor: const Color(0xFF1E2230),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: email,
                              readOnly: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: const Icon(Icons.email_outlined, color: Colors.white70),
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintStyle: const TextStyle(color: Colors.white60),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.white.withOpacity(0.18)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.deepPurple.shade200, width: 1.4),
                                ),
                                filled: true,
                                fillColor: const Color(0xFF1E2230),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Changes are saved locally on this device',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User Info Section
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openProfileSheet,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.shade100,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Icon(
                      Icons.account_circle,
                      size: 40,
                      color: Colors.deepPurple.shade700,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.edit, size: 18, color: Colors.deepPurple.shade400),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.currentUser?.email ?? 'Email not set',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _address,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Appearance Settings
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Appearance",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.brightness_6),
                  title: const Text("Theme"),
                  subtitle: Text(
                    widget.currentTheme == ThemeMode.dark
                        ? "Dark"
                        : widget.currentTheme == ThemeMode.light
                            ? "Light"
                            : "System",
                  ),
                  trailing: DropdownButton<ThemeMode>(
                    value: widget.currentTheme,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text("System"),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text("Light"),
                      ),
                      DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text("Dark"),
                      ),
                    ],
                    onChanged: (mode) {
                      if (mode != null) widget.onThemeChanged(mode);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Currency Settings
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Currency",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_money),
                  title: const Text("Default Currency"),
                  subtitle: Text(widget.currentCurrency),
                  trailing: DropdownButton<String>(
                    value: widget.currentCurrency,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: "\$", child: Text("\$ USD")),
                      DropdownMenuItem(value: "₹", child: Text("₹ INR")),
                      DropdownMenuItem(value: "₨", child: Text("₨ PKR")),
                      DropdownMenuItem(value: "€", child: Text("€ EUR")),
                      DropdownMenuItem(value: "£", child: Text("£ GBP")),
                      DropdownMenuItem(value: "¥", child: Text("¥ JPY")),
                    ],
                    onChanged: (curr) {
                      if (curr != null) widget.onCurrencyChanged(curr);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Notifications & Preferences
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Notifications",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Budget Alerts"),
                  subtitle: const Text("Get notified when approaching budget"),
                  value: _notifications,
                  onChanged: (value) async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('notifications', value);
                    setState(() => _notifications = value);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Data & Privacy
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Data & Privacy",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.download, color: Colors.blue),
                  title: const Text("Export Data"),
                  subtitle: const Text("Download your transactions as CSV"),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Export feature coming soon")),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup, color: Colors.green),
                  title: const Text("Cloud Backup"),
                  subtitle: const Text("Auto-backup data to cloud"),
                  trailing: Switch(
                    value: true,
                    onChanged: (value) => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Backup enabled")),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // App Info
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "About",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info),
                  title: const Text("App Version"),
                  subtitle: const Text("1.0.0"),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help, color: Colors.orange),
                  title: const Text("Help & Support"),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Support features coming soon")),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Account Settings
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Account",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    "Sign Out",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                  ),
                  onTap: () async {
                    await auth.signOut();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

/* ===================== AUTH PAGE ===================== */

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool isLogin = true;
  bool isLoading = false;

  Future<void> authenticate() async {
    if (email.text.trim().isEmpty || password.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        await auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text.trim(),
        );
      } else {
        await auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text.trim(),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? "Authentication failed")),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      size: 80,
                      color: Colors.deepPurple.shade600,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Spending Tracker",
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isLogin ? "Welcome back!" : "Create your account",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: const Icon(Icons.email),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : authenticate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isLogin ? "Sign In" : "Sign Up",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? "Don't have an account? Sign Up"
                            : "Already have an account? Sign In",
                        style: TextStyle(color: Colors.deepPurple.shade600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ===================== PIE CHART PAINTER ===================== */

class PieChartPainter extends CustomPainter {
  final Map<String, double> data;
  final double total;

  PieChartPainter({required this.data, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width < size.height ? size.width / 2.5 : size.height / 2.5;
    
    double startAngle = -90 * (3.14159 / 180); // Start from top

    data.forEach((category, amount) {
      final sweepAngle = (amount / total) * 2 * 3.14159;
      final paint = Paint()
        ..color = _getCategoryColor(category)
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      startAngle += sweepAngle;
    });

    // Draw center circle for donut effect
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.6, centerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Color _getCategoryColor(String category) {
  final colors = {
    'Food': Colors.orange,
    'Transport': Colors.blue,
    'Rent': Colors.purple,
    'Utilities': Colors.cyan,
    'Entertainment': Colors.pink,
    'Health': Colors.red,
    'Shopping': Colors.green,
    'Education': Colors.indigo,
    'Insurance': Colors.teal,
    'Other': Colors.grey,
    'Salary': Colors.lightGreen,
    'Freelance': Colors.amber,
    'Investment': Colors.deepPurple,
    'Bonus': Colors.lime,
    'Gift': Colors.pinkAccent,
  };
  return colors[category] ?? Colors.blueGrey;
}

/* ===================== BUDGET PAGE ===================== */

class BudgetPage extends StatefulWidget {
  final String currency;

  const BudgetPage({super.key, required this.currency});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('budgets')
            .where('uid', isEqualTo: uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Budget Manager",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle, size: 32),
                            color: Colors.deepPurple,
                            onPressed: () => _showAddBudgetDialog(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Set spending limits for categories",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Budget List
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        Icon(Icons.account_balance_wallet_outlined, 
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          "No budgets set",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Tap + to create your first budget",
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...snapshot.data!.docs.map((budget) {
                  return FutureBuilder<double>(
                    future: _getSpentAmount(
                      uid,
                      budget['category'],
                      budget['period'],
                    ),
                    builder: (context, spentSnapshot) {
                      final limit = (budget['amount'] as num).toDouble();
                      final spent = spentSnapshot.data ?? 0.0;
                      final percentage = limit > 0 ? (spent / limit) : 0.0;
                      final isOverBudget = spent > limit;

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: _getCategoryColor(budget['category'])
                                              .withAlpha(40),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          _getCategoryIcon(budget['category']),
                                          color: _getCategoryColor(budget['category']),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            budget['category'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            budget['period'].toString().toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.grey.shade600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'delete') {
                                        budget.reference.delete();
                                      } else if (value == 'edit') {
                                        _showEditBudgetDialog(context, budget);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    "${widget.currency} ${spent.toStringAsFixed(2)} / ${limit.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isOverBudget ? Colors.red : Colors.green,
                                    ),
                                  ),
                                  Text(
                                    "${(percentage * 100).toStringAsFixed(0)}%",
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: isOverBudget 
                                          ? Colors.red 
                                          : percentage > 0.8 
                                              ? Colors.orange 
                                              : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: percentage > 1 ? 1 : percentage,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isOverBudget
                                        ? Colors.red
                                        : percentage > 0.8
                                            ? Colors.orange
                                            : Colors.green,
                                  ),
                                  minHeight: 10,
                                ),
                              ),
                              if (isOverBudget)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber_rounded, 
                                          size: 16, color: Colors.red.shade700),
                                      const SizedBox(width: 6),
                                      Text(
                                        "Over budget by ${widget.currency} ${(spent - limit).toStringAsFixed(2)}",
                                        style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Future<double> _getSpentAmount(String uid, String category, String period) async {
    final now = DateTime.now();
    DateTime startDate;

    switch (period) {
      case 'daily':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'weekly':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(startDate.year, startDate.month, startDate.day);
        break;
      case 'monthly':
        startDate = DateTime(now.year, now.month, 1);
        break;
      default:
        startDate = DateTime(now.year, now.month, 1);
    }

    final snapshot = await db
        .collection('transactions')
        .where('uid', isEqualTo: uid)
        .where('type', isEqualTo: 'expense')
        .where('category', isEqualTo: category)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .get();

    double total = 0;
    for (var doc in snapshot.docs) {
      total += (doc['amount'] as num).toDouble();
    }
    return total;
  }

  void _showAddBudgetDialog(BuildContext context) {
    final amountController = TextEditingController();
    late String selectedCategory = 'Food';
    late String selectedPeriod = 'monthly';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Create Budget"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: "Category",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    'Food', 'Transport', 'Rent', 'Utilities', 
                    'Entertainment', 'Health', 'Shopping', 
                    'Education', 'Insurance', 'Other'
                  ].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                  onChanged: (v) => setDialogState(() => selectedCategory = v ?? 'Food'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedPeriod,
                  decoration: const InputDecoration(
                    labelText: "Period",
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedPeriod = v ?? 'monthly'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: "Budget Amount",
                    prefixText: "${widget.currency} ",
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount != null && amount > 0) {
                  try {
                    await db.collection('budgets').add({
                      'uid': auth.currentUser!.uid,
                      'category': selectedCategory,
                      'amount': amount,
                      'period': selectedPeriod,
                      'createdAt': Timestamp.now(),
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Budget created successfully')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter a valid amount')),
                    );
                  }
                }
              },
              child: const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditBudgetDialog(BuildContext context, QueryDocumentSnapshot budget) {
    final amountController = TextEditingController(
      text: budget['amount'].toString(),
    );
    String selectedPeriod = budget['period'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Edit ${budget['category']} Budget"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedPeriod,
                decoration: const InputDecoration(
                  labelText: "Period",
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                  DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                ],
                onChanged: (v) => setDialogState(() => selectedPeriod = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Budget Amount",
                  prefixText: "${widget.currency} ",
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                if (amount != null && amount > 0) {
                  await budget.reference.update({
                    'amount': amount,
                    'period': selectedPeriod,
                  });
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    final icons = {
      'Food': Icons.restaurant,
      'Transport': Icons.directions_car,
      'Rent': Icons.home,
      'Utilities': Icons.bolt,
      'Entertainment': Icons.movie,
      'Health': Icons.local_hospital,
      'Shopping': Icons.shopping_bag,
      'Education': Icons.school,
      'Insurance': Icons.security,
      'Other': Icons.category,
    };
    return icons[category] ?? Icons.category;
  }
}
