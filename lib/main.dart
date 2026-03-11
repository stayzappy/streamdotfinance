import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:webthree/webthree.dart' as web3;
import 'package:convert/convert.dart'; 
import 'package:http/http.dart' as http; // NEW: HTTP package for live pricing
import 'dart:convert'; // NEW: For JSON decoding
import 'firebase_options.dart';

// ==============================================================
// 1. STRICT JS INTEROP DEFINITIONS (EVM / PVM Bridge)
// ==============================================================
@JS('window.ethereum')
external Ethereum? get ethereum;

@JS('window.talismanEth')
external Ethereum? get talismanEth;

@JS('window.SubWallet')
external Ethereum? get subWallet;

@JS()
extension type Ethereum._(JSObject _) implements JSObject {
  external JSPromise request(RequestArguments args);
  external bool? get isMetaMask;
  external bool? get isRabby;
}

@JS()
@anonymous
extension type RequestArguments._(JSObject _) implements JSObject {
  external factory RequestArguments({
    required JSString method,
    JSAny? params,
  });
}

// ==============================================================
// 2. DATA MODELS
// ==============================================================
class StreamData {
  final int id;
  final String sender;
  final String recipient;
  final String asset;
  final BigInt deposit;
  final BigInt withdrawnAmount;
  final BigInt remainingBalance; 
  final int startTime;
  final int stopTime;

  StreamData({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.asset,
    required this.deposit,
    required this.withdrawnAmount,
    required this.remainingBalance, 
    required this.startTime,
    required this.stopTime,
  });
}

// ==============================================================
// 3. WEB3 ABI ENCODER & DECODER SERVICE
// ==============================================================
class Web3Service {
  static const String contractAddress = "0x9d939233A26ff54780F980513C1D4420B8C2C6de";
  
  static const String _abi = '''[
    {
      "inputs": [
        {"internalType": "address", "name": "recipient", "type": "address"},
        {"internalType": "address", "name": "asset", "type": "address"},
        {"internalType": "uint256", "name": "deposit", "type": "uint256"},
        {"internalType": "uint256", "name": "startTime", "type": "uint256"},
        {"internalType": "uint256", "name": "stopTime", "type": "uint256"}
      ],
      "name": "createStream",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "payable",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "uint256", "name": "streamId", "type": "uint256"},
        {"internalType": "uint256", "name": "amount", "type": "uint256"}
      ],
      "name": "withdrawFromStream",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "streamId", "type": "uint256"}],
      "name": "cancelStream",
      "outputs": [],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {"internalType": "address", "name": "spender", "type": "address"},
        {"internalType": "uint256", "name": "amount", "type": "uint256"}
      ],
      "name": "approve",
      "outputs": [{"internalType": "bool", "name": "", "type": "bool"}],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "nextStreamId",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "name": "streams",
      "outputs": [
        {"internalType": "address", "name": "sender", "type": "address"},
        {"internalType": "address", "name": "recipient", "type": "address"},
        {"internalType": "address", "name": "asset", "type": "address"},
        {"internalType": "uint256", "name": "deposit", "type": "uint256"},
        {"internalType": "uint256", "name": "ratePerSecond", "type": "uint256"},
        {"internalType": "uint256", "name": "startTime", "type": "uint256"},
        {"internalType": "uint256", "name": "stopTime", "type": "uint256"},
        {"internalType": "uint256", "name": "remainingBalance", "type": "uint256"},
        {"internalType": "uint256", "name": "withdrawnAmount", "type": "uint256"}
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "streamId", "type": "uint256"}],
      "name": "unlockedBalanceOf",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [{"internalType": "uint256", "name": "streamId", "type": "uint256"}],
      "name": "availableToWithdraw",
      "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}],
      "stateMutability": "view",
      "type": "function"
    }
  ]''';

  static final _contract = web3.DeployedContract(
    web3.ContractAbi.fromJson(_abi, 'StreamDot'),
    web3.EthereumAddress.fromHex(contractAddress, enforceEip55: false),
  );

  static String encodeApprove(BigInt amount) {
    final function = _contract.function('approve');
    final data = function.encodeCall([
      web3.EthereumAddress.fromHex(contractAddress, enforceEip55: false),
      amount
    ]);
    return "0x${hex.encode(data)}"; 
  }

  static String encodeCreateStream(String recipient, String asset, BigInt deposit, BigInt startTime, BigInt stopTime) {
    final function = _contract.function('createStream');
    final data = function.encodeCall([
      web3.EthereumAddress.fromHex(recipient, enforceEip55: false),
      web3.EthereumAddress.fromHex(asset, enforceEip55: false),
      deposit,
      startTime,
      stopTime
    ]);
    return "0x${hex.encode(data)}"; 
  }

  static String encodeWithdrawFromStream(BigInt streamId, BigInt amount) {
    final function = _contract.function('withdrawFromStream');
    final data = function.encodeCall([streamId, amount]);
    return "0x${hex.encode(data)}";
  }

  static String encodeCancelStream(BigInt streamId) {
    final function = _contract.function('cancelStream');
    final data = function.encodeCall([streamId]);
    return "0x${hex.encode(data)}";
  }

  static String encodeAvailableToWithdraw(BigInt streamId) {
    final function = _contract.function('availableToWithdraw');
    final data = function.encodeCall([streamId]);
    return "0x${hex.encode(data)}";
  }

  static String encodeNextStreamId() {
    final function = _contract.function('nextStreamId');
    final data = function.encodeCall([]);
    return "0x${hex.encode(data)}";
  }

  static String encodeGetStream(BigInt streamId) {
    final function = _contract.function('streams');
    final data = function.encodeCall([streamId]);
    return "0x${hex.encode(data)}";
  }

  static BigInt decodeUint256(String hexData) {
    final cleanHex = hexData.startsWith('0x') ? hexData.substring(2) : hexData;
    if (cleanHex.isEmpty) return BigInt.zero;
    return BigInt.parse(cleanHex, radix: 16);
  }

  static List<dynamic> decodeStreamData(String hexData) {
    final function = _contract.function('streams');
    return function.decodeReturnValues(hexData);
  }
}

// ==============================================================
// 4. MAIN ENTRY POINT
// ==============================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("🔥 TRACE: Firebase Init Error: $e");
  }
  runApp(const MainApp());
}

// ==============================================================
// 5. ROOT APPLICATION
// ==============================================================
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamDot Finance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE6007A),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      home: const LandingScreen(),
    );
  }
}

// ==============================================================
// 6. LANDING / WALLET CONNECTION SCREEN
// ==============================================================
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _isConnecting = false;
  String? _connectedAddress;
  Ethereum? _targetProvider; 
  String _statusMessage = "Select your wallet to enter the protocol.";
  
  String? _targetStreamId;
  String? _targetRecipientAddress;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkDeepLink();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _checkDeepLink() {
    try {
      final uri = Uri.base;
      if (uri.queryParameters.containsKey('stream') && uri.queryParameters.containsKey('to')) {
        setState(() {
          _targetStreamId = uri.queryParameters['stream'];
          _targetRecipientAddress = uri.queryParameters['to'];
        });
        debugPrint("🔥 TRACE: Deep link detected for stream ID: $_targetStreamId, restricted to $_targetRecipientAddress");
      }
    } catch (e) {
      debugPrint("🔥 TRACE: Error parsing deep link: $e");
    }
  }

  void _disconnectWallet() {
    setState(() {
      _connectedAddress = null;
      _targetProvider = null;
      _statusMessage = "Select your wallet to enter the protocol.";
    });
  }

  Future<void> _connectEVMWallet(String walletName) async {
    Navigator.of(context).pop();
    
    Ethereum? provider;
    if (walletName == "Talisman") {
      provider = talismanEth;
    } else if (walletName == "SubWallet") {
      provider = subWallet;
    } else if (walletName == "Rabby") {
      if (ethereum != null && ethereum!.isRabby == true) {
        provider = ethereum;
      } else {
        provider = null;
      }
    } else {
      provider = ethereum;
    }

    if (provider == null) {
      setState(() { _statusMessage = "$walletName not detected or is inactive."; });
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = "Requesting connection to $walletName...";
    });

    try {
      try {
        final permArgs = RequestArguments(
          method: 'wallet_requestPermissions'.toJS,
          params: [{'eth_accounts': {}}].jsify(),
        );
        await provider.request(permArgs).toDart;
      } catch (e) {
        String errorString = "";
        if (e is JSObject) {
          try {
            final jsJson = globalContext.getProperty('JSON'.toJS) as JSObject;
            final jsString = jsJson.callMethod('stringify'.toJS, e as JSAny) as JSString?;
            errorString = jsString?.toDart.toLowerCase() ?? e.toString().toLowerCase();
          } catch (_) {
            errorString = e.toString().toLowerCase();
          }
        } else {
          errorString = e.toString().toLowerCase();
        }
        
        if (errorString.contains("4001") || errorString.contains("rejected")) {
          setState(() {
            _statusMessage = "Connection rejected by user.";
            _isConnecting = false;
          });
          return; 
        }
      }

      final args = RequestArguments(method: 'eth_requestAccounts'.toJS);
      final resultAny = await provider.request(args).toDart;
      final jsArray = resultAny as JSArray;
      
      if (jsArray.length > 0) {
        final address = (jsArray[0] as JSString).toDart;
        
        if (_targetRecipientAddress != null && address.toLowerCase() != _targetRecipientAddress!.toLowerCase()) {
          debugPrint("🔥 TRACE: Wallet mismatch. Expected $_targetRecipientAddress, got $address");
          setState(() {
            _isConnecting = false;
            _statusMessage = "Access Denied: Connected wallet does not match.";
          });
          
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Access Denied!\nPlease switch your wallet to: ${_targetRecipientAddress!.substring(0, 6)}...${_targetRecipientAddress!.substring(_targetRecipientAddress!.length - 4)}",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.redAccent.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              margin: const EdgeInsets.all(24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          return;
        }

        setState(() {
          _connectedAddress = address;
          _targetProvider = provider;
          _statusMessage = "Connected securely.";
        });

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(
              connectedAddress: _connectedAddress!,
              provider: _targetProvider!,
              initialTabIndex: _targetStreamId != null ? 1 : 0, 
            ),
          ),
        );
      }
    } catch (e) {
      setState(() { _statusMessage = "Connection failed."; });
    } finally {
      setState(() { _isConnecting = false; });
    }
  }

  void _showWalletSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, 
      builder: (BuildContext context) {
        return SafeArea( 
          child: SingleChildScrollView( 
            child: Container(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 40),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 24),
                  const Text("Connect Wallet", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text("Select a provider to access the Passet Hub.", style: TextStyle(color: Colors.grey[400])),
                  const SizedBox(height: 32),
                  _buildWalletOption("Talisman", Icons.auto_awesome, Colors.orangeAccent),
                  _buildWalletOption("SubWallet", Icons.account_tree_rounded, Colors.blueAccent),
                  _buildWalletOption("MetaMask", Icons.pets, Colors.orange),
                  _buildWalletOption("Rabby", Icons.security, Colors.deepPurpleAccent),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWalletOption(String name, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        onTap: () => _connectEVMWallet(name),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(color: Colors.black12, border: Border.all(color: Colors.white10), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 24)),
              const SizedBox(width: 16),
              Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
              const Spacer(),
              const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // FIXED: Manual keyboard handler to support arrow key scrolling on Web
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      double offset = 0;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) offset = 50;
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp) offset = -50;
      else if (event.logicalKey == LogicalKeyboardKey.pageDown) offset = 200;
      else if (event.logicalKey == LogicalKeyboardKey.pageUp) offset = -200;

      if (offset != 0) {
        final target = (_scrollController.offset + offset).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(target);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent, // Attach keyboard scrolling listener
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height > 800 ? MediaQuery.of(context).size.height : 800,
            decoration: const BoxDecoration(
              gradient: RadialGradient(center: Alignment.topRight, radius: 1.5, colors: [Color(0xFF1E293B), Color(0xFF0F172A)]),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6007A).withOpacity(0.1),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: const Color(0xFFE6007A).withOpacity(0.2), blurRadius: 40, spreadRadius: 10)],
                      ),
                      child: const Icon(Icons.waves_rounded, size: 80, color: Color(0xFFE6007A)),
                    ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 32),
                    
                    if (_targetStreamId != null && _targetRecipientAddress != null) ...[
                      Container(
                        padding: const EdgeInsets.all(32),
                        constraints: const BoxConstraints(maxWidth: 500),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 2),
                          boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.1), blurRadius: 40)],
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.celebration, color: Colors.greenAccent, size: 48),
                            const SizedBox(height: 16),
                            const Text("You've received an Income Stream!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            Text("Please connect the exact wallet address below to verify your identity, view your live balance, and withdraw your funds:", style: TextStyle(color: Colors.grey[400], fontSize: 16), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                              child: Text(
                                "${_targetRecipientAddress!.substring(0, 6)}...${_targetRecipientAddress!.substring(_targetRecipientAddress!.length - 4)}",
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1),
                              ),
                            ),
                          ],
                        )
                      ).animate().fadeIn().slideY(begin: 0.1, end: 0),
                      const SizedBox(height: 24),
                      
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _targetStreamId = null;
                            _targetRecipientAddress = null;
                            _statusMessage = "Select your wallet to enter the protocol.";
                          });
                        },
                        child: const Text("Not you? Create your own stream today ->", style: TextStyle(color: Color(0xFF3B82F6), fontSize: 16)),
                      ).animate().fadeIn(delay: 300.ms),
                      const SizedBox(height: 32),
                    ] else ...[
                      Text(
                        "StreamDot Finance",
                        style: GoogleFonts.outfit(fontSize: 56, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -1.5),
                        textAlign: TextAlign.center,
                      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2, end: 0),
                      const SizedBox(height: 16),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Text(
                          "The Universal Native Asset Payroll Protocol on Polkadot Passet Hub. Stream PAS and Asset Hub tokens securely by the second.",
                          style: TextStyle(fontSize: 18, color: Colors.grey[400], height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
                      const SizedBox(height: 48),
                    ],
        
                    if (_connectedAddress != null && _targetProvider != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Colors.greenAccent),
                            const SizedBox(width: 12),
                            Text(
                              "${_connectedAddress!.substring(0, 6)}...${_connectedAddress!.substring(_connectedAddress!.length - 4)}",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                            ),
                          ],
                        ),
                      ).animate().fadeIn().scale(),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => DashboardScreen(
                                    connectedAddress: _connectedAddress!,
                                    provider: _targetProvider!,
                                    initialTabIndex: _targetStreamId != null ? 1 : 0, 
                                  ),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text("Enter Dashboard", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          ).animate().fadeIn(delay: 300.ms),
                          const SizedBox(width: 16),
                          OutlinedButton(
                            onPressed: _disconnectWallet,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                              side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Icon(Icons.logout, color: Colors.redAccent),
                          ).animate().fadeIn(delay: 400.ms),
                        ],
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: _isConnecting ? null : _showWalletSelector,
                        icon: _isConnecting 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.account_balance_wallet, size: 24, color: Colors.white),
                        label: Text(_isConnecting ? "Connecting..." : "Connect Web3 Wallet", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE6007A),
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 8,
                          shadowColor: const Color(0xFFE6007A).withOpacity(0.5),
                        ),
                      ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, end: 0),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains("rejected") || _statusMessage.contains("Denied") ? Colors.redAccent : Colors.grey[500],
                          fontSize: 14,
                        ),
                      ).animate().fadeIn(delay: 800.ms),
                    ]
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

// ==============================================================
// 7. DASHBOARD SCREEN (STREAM CREATION & VIEWER)
// ==============================================================
class DashboardScreen extends StatefulWidget {
  final String connectedAddress;
  final Ethereum provider;
  final int initialTabIndex;

  const DashboardScreen({
    super.key, 
    required this.connectedAddress, 
    required this.provider,
    this.initialTabIndex = 0,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _selectedIndex; 

  final _recipientCtrl = TextEditingController();
  final _customAssetCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _durationDaysCtrl = TextEditingController();
  
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  String _selectedToken = "Native PAS / DOT";
  final Map<String, String> _precompiles = {
    "Native PAS / DOT": "0x0000000000000000000000000000000000000000", 
    "USDT": "0x0000000000000000000000000000000001200001", 
    "USDC": "0x0000000000000000000000000000000001200002", 
    "Custom ERC20": "custom",
  };
  
  // LIVE ORACLE: Now fetches real data instead of static mocks
  final Map<String, double> _usdPrices = {
    "PAS": 0.00,
    "USDT": 1.00,
    "USDC": 1.00,
    "Token": 1.00, 
  };
  
  bool _isTransacting = false;
  String _txStatusMessage = ""; 
  String? _txHash;
  int? _lastCreatedStreamId;
  
  bool _isLoadingStreams = false;
  List<StreamData> _myStreams = [];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _focusNode.requestFocus();
    
    // Fetch real-time market data on load
    _fetchLivePrices();
    
    if (_selectedIndex == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchMyStreams();
      });
    }
  }

  @override
  void dispose() {
    _recipientCtrl.dispose();
    _customAssetCtrl.dispose();
    _amountCtrl.dispose();
    _durationDaysCtrl.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // FIXED: Real-time price oracle integration using public Binance API
  Future<void> _fetchLivePrices() async {
    try {
      debugPrint("🔥 TRACE: Fetching live DOT/USDT pricing from public Oracle...");
      final response = await http.get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=DOTUSDT'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final double dotPrice = double.parse(data['price']);
        setState(() {
          _usdPrices["PAS"] = dotPrice; // Map DOT price directly to PAS
          _usdPrices["DOT"] = dotPrice;
        });
        debugPrint("🔥 TRACE: Live Oracle success. Current Price: \$$dotPrice");
      }
    } catch (e) {
      debugPrint("🔥 TRACE: Live Oracle failed. Retaining fallback. Error: $e");
    }
  }

  // FIXED: Manual keyboard handler to support arrow key scrolling on Web
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      double offset = 0;
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) offset = 50;
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp) offset = -50;
      else if (event.logicalKey == LogicalKeyboardKey.pageDown) offset = 200;
      else if (event.logicalKey == LogicalKeyboardKey.pageUp) offset = -200;

      if (offset != 0) {
        final target = (_scrollController.offset + offset).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(target);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _resetForm() {
    _recipientCtrl.clear();
    _customAssetCtrl.clear();
    _amountCtrl.clear();
    _durationDaysCtrl.clear();
    setState(() {
      _selectedToken = "Native PAS / DOT";
      _txHash = null;
      _lastCreatedStreamId = null;
      _isTransacting = false;
      _txStatusMessage = "";
    });
  }

  void _copyViralLink(int streamId, String targetAddress) {
    final url = "https://streamdotfinance.web.app/?stream=$streamId&to=$targetAddress";
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Secure link copied! Share this with your recipient."), backgroundColor: Color(0xFF3B82F6)),
    );
  }

  Future<bool> _ensureCorrectNetwork() async {
    debugPrint("🔥 TRACE: Gatekeeper evaluating current network...");
    try {
      final chainIdArgs = RequestArguments(method: 'eth_chainId'.toJS);
      final currentChainHexAny = await widget.provider.request(chainIdArgs).toDart;
      final currentChainHex = (currentChainHexAny as JSString).toDart.toLowerCase();
      
      const targetChainId = '0x190f1b41'; 
      debugPrint("🔥 TRACE: Current Chain ID is $currentChainHex. Target is $targetChainId");
      
      if (currentChainHex != targetChainId) {
        setState(() {
          _txStatusMessage = "Please switch to Polkadot Testnet...";
        });
        
        try {
          final switchArgs = RequestArguments(
            method: 'wallet_switchEthereumChain'.toJS,
            params: [{'chainId': targetChainId}].jsify()
          );
          await widget.provider.request(switchArgs).toDart;
          debugPrint("🔥 TRACE: Gatekeeper forced network switch successfully.");
          return true;
        } catch (e) {
          String errorString = "";
          if (e is JSObject) {
            try {
              final jsJson = globalContext.getProperty('JSON'.toJS) as JSObject;
              final jsString = jsJson.callMethod('stringify'.toJS, e as JSAny) as JSString?;
              errorString = jsString?.toDart.toLowerCase() ?? e.toString().toLowerCase();
            } catch (_) {
              errorString = e.toString().toLowerCase();
            }
          } else {
            errorString = e.toString().toLowerCase();
          }

          if (errorString.contains('4902') || errorString.contains('unrecognized chain')) {
             debugPrint("🔥 TRACE: Network missing. Adding Polkadot Testnet via RPC...");
             final addArgs = RequestArguments(
               method: 'wallet_addEthereumChain'.toJS,
               params: [{
                 'chainId': targetChainId,
                 'chainName': 'Polkadot Testnet (Paseo)',
                 'rpcUrls': ['https://eth-rpc-testnet.polkadot.io/'],
                 'nativeCurrency': {
                   'name': 'Paseo',
                   'symbol': 'PAS',
                   'decimals': 18
                 },
                 'blockExplorerUrls': ['https://blockscout-testnet.polkadot.io/']
               }].jsify()
             );
             await widget.provider.request(addArgs).toDart;
             return true;
          }
          debugPrint("🔥 TRACE: Gatekeeper failed. Switch rejected or threw error: $errorString");
          return false;
        }
      }
      return true; 
    } catch (e) {
       debugPrint("🔥 TRACE: Gatekeeper completely failed checking network: $e");
       return false;
    }
  }

  Future<void> _fetchMyStreams() async {
    setState(() {
      _isLoadingStreams = true;
      _myStreams.clear();
      _txHash = null;
    });
    
    final isCorrectNetwork = await _ensureCorrectNetwork();
    if (!isCorrectNetwork) {
      setState(() => _isLoadingStreams = false);
      return;
    }

    debugPrint("🔥 TRACE: Fetching total streams on PVM...");

    try {
      final idParams = {
        'to': Web3Service.contractAddress,
        'data': Web3Service.encodeNextStreamId(),
      }.jsify();
      
      final idArgs = RequestArguments(method: 'eth_call'.toJS, params: [idParams, 'latest'.toJS].jsify());
      final idResultHex = (await widget.provider.request(idArgs).toDart as JSString).toDart;
      
      final totalStreams = Web3Service.decodeUint256(idResultHex).toInt();
      debugPrint("🔥 TRACE: Total streams found globally: $totalStreams");
      
      List<StreamData> fetchedStreams = [];

      for (int i = totalStreams - 1; i >= 1; i--) {
        final streamParams = {
          'to': Web3Service.contractAddress,
          'data': Web3Service.encodeGetStream(BigInt.from(i)),
        }.jsify();
        
        final streamArgs = RequestArguments(method: 'eth_call'.toJS, params: [streamParams, 'latest'.toJS].jsify());
        final streamResultHex = (await widget.provider.request(streamArgs).toDart as JSString).toDart;
        
        if (streamResultHex == "0x" || streamResultHex.length < 10) continue;

        final decodedData = Web3Service.decodeStreamData(streamResultHex);
        final sender = (decodedData[0] as web3.EthereumAddress).hex.toLowerCase();
        final recipient = (decodedData[1] as web3.EthereumAddress).hex.toLowerCase();
        final userAddress = widget.connectedAddress.toLowerCase();

        if (sender == userAddress || recipient == userAddress) {
          fetchedStreams.add(StreamData(
            id: i,
            sender: sender,
            recipient: recipient,
            asset: (decodedData[2] as web3.EthereumAddress).hex,
            deposit: decodedData[3] as BigInt,
            withdrawnAmount: decodedData[8] as BigInt,
            remainingBalance: decodedData[7] as BigInt,
            startTime: (decodedData[5] as BigInt).toInt(),
            stopTime: (decodedData[6] as BigInt).toInt(),
          ));
        }
      }

      setState(() {
        _myStreams = fetchedStreams;
      });

    } catch (e) {
      debugPrint("🔥 TRACE: eth_call Fetch Error: $e");
    } finally {
      setState(() => _isLoadingStreams = false);
    }
  }

  Future<void> _createStream() async {
    debugPrint("🔥 TRACE: User clicked Initialize Stream. Validating inputs...");
    if (_recipientCtrl.text.isEmpty || _amountCtrl.text.isEmpty || _durationDaysCtrl.text.isEmpty) {
      debugPrint("🔥 TRACE: Aborted. Missing input fields.");
      return;
    }

    final assetAddress = _selectedToken == "Custom ERC20" ? _customAssetCtrl.text : _precompiles[_selectedToken]!;
    if (assetAddress.isEmpty) return;

    if (_recipientCtrl.text.toLowerCase() == widget.connectedAddress.toLowerCase()) {
      setState(() => _txStatusMessage = "Error: Cannot stream to your own wallet.");
      return;
    }

    setState(() {
      _isTransacting = true;
      _txHash = null;
      _txStatusMessage = "Checking network...";
    });

    final isCorrectNetwork = await _ensureCorrectNetwork();
    if (!isCorrectNetwork) {
      debugPrint("🔥 TRACE: Aborted. Network gatekeeper failed.");
      setState(() {
        _isTransacting = false;
        _txStatusMessage = "";
      });
      return;
    }

    try {
      debugPrint("🔥 TRACE: Parsing mathematical amounts...");
      final double parsedVal = double.tryParse(_amountCtrl.text) ?? 0.0;
      if (parsedVal <= 0.0) {
         setState(() => _txStatusMessage = "Invalid amount entered.");
         debugPrint("🔥 TRACE: Aborted. Amount parses to 0 or less.");
         return;
      }
      
      final rawDeposit = BigInt.from(parsedVal * 1000000) * BigInt.from(10).pow(12);
      
      final currentTimestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round();
      final durationSeconds = int.parse(_durationDaysCtrl.text) * 86400; 
      
      final durationBig = BigInt.from(durationSeconds);
      final remainder = rawDeposit % durationBig;
      final depositAmount = rawDeposit - remainder;

      final isNative = assetAddress == "0x0000000000000000000000000000000000000000";
      debugPrint("🔥 TRACE: Is Native Gas Router? $isNative");

      if (!isNative) {
        setState(() { _txStatusMessage = "Step 1/2: Requesting Token Approval..."; });
        debugPrint("🔥 TRACE: Initiating Approval Transaction...");
        final approvePayload = Web3Service.encodeApprove(depositAmount);
        
        final approveParams = {
          'to': assetAddress, 
          'from': widget.connectedAddress,
          'data': approvePayload,
        }.jsify();

        final approveArgs = RequestArguments(
          method: 'eth_sendTransaction'.toJS,
          params: [approveParams].jsify(),
        );

        await widget.provider.request(approveArgs).toDart;
        await Future.delayed(const Duration(seconds: 1));
      }

      setState(() {
        _txStatusMessage = isNative ? "Confirming Stream Creation..." : "Step 2/2: Confirming Stream Creation...";
      });

      debugPrint("🔥 TRACE: Initiating Create Stream Transaction...");
      final startTime = BigInt.from(currentTimestamp + 60); 
      final stopTime = BigInt.from(currentTimestamp + 60 + durationSeconds);

      final encodedPayload = Web3Service.encodeCreateStream(
        _recipientCtrl.text,
        assetAddress,
        depositAmount,
        startTime,
        stopTime
      );

      final createParams = {
        'to': Web3Service.contractAddress,
        'from': widget.connectedAddress,
        'data': encodedPayload,
        if (isNative) 'value': "0x${depositAmount.toRadixString(16)}", 
      }.jsify();

      final createArgs = RequestArguments(
        method: 'eth_sendTransaction'.toJS,
        params: [createParams].jsify(),
      );

      final result = await widget.provider.request(createArgs).toDart;
      final txHash = (result as JSString).toDart;
      debugPrint("🔥 TRACE: Stream Created Successfully. Hash: $txHash");

      final idParams = {'to': Web3Service.contractAddress, 'data': Web3Service.encodeNextStreamId()}.jsify();
      final idArgs = RequestArguments(method: 'eth_call'.toJS, params: [idParams, 'latest'.toJS].jsify());
      final idResultHex = (await widget.provider.request(idArgs).toDart as JSString).toDart;
      final nextId = Web3Service.decodeUint256(idResultHex).toInt();

      setState(() {
        _txHash = txHash;
        _lastCreatedStreamId = nextId - 1;
      });

    } catch (e) {
      debugPrint("🔥 TRACE: Transaction Failed or Rejected: $e");
    } finally {
      setState(() {
        _isTransacting = false;
        _txStatusMessage = "";
      });
    }
  }

  Future<void> _withdrawStream(int streamId) async {
    setState(() {
      _isTransacting = true;
      _txStatusMessage = "Calculating available balance...";
    });

    try {
      final availParams = {
        'to': Web3Service.contractAddress,
        'data': Web3Service.encodeAvailableToWithdraw(BigInt.from(streamId)),
      }.jsify();
      
      final availArgs = RequestArguments(method: 'eth_call'.toJS, params: [availParams, 'latest'.toJS].jsify());
      final availResultHex = (await widget.provider.request(availArgs).toDart as JSString).toDart;
      final availableBigInt = Web3Service.decodeUint256(availResultHex);

      if (availableBigInt <= BigInt.zero) {
        debugPrint("🔥 TRACE: Nothing to withdraw yet.");
        setState(() { _isTransacting = false; });
        return;
      }

      setState(() { _txStatusMessage = "Confirming Withdrawal in Wallet..."; });
      
      final payload = Web3Service.encodeWithdrawFromStream(BigInt.from(streamId), availableBigInt);
      
      final txParams = {
        'to': Web3Service.contractAddress,
        'from': widget.connectedAddress,
        'data': payload,
      }.jsify();

      final txArgs = RequestArguments(method: 'eth_sendTransaction'.toJS, params: [txParams].jsify());
      final result = await widget.provider.request(txArgs).toDart;
      final txHash = (result as JSString).toDart;
      debugPrint("🔥 TRACE: Withdrawal Successful. Hash: $txHash");

      setState(() { _txStatusMessage = "Processing withdrawal..."; });
      await Future.delayed(const Duration(seconds: 3));
      _fetchMyStreams();

    } catch (e) {
      debugPrint("🔥 TRACE: Withdraw Failed: $e");
    } finally {
      setState(() { _isTransacting = false; });
    }
  }

  Future<void> _cancelStream(int streamId) async {
    setState(() {
      _isTransacting = true;
      _txStatusMessage = "Confirming Cancellation in Wallet...";
    });

    try {
      final payload = Web3Service.encodeCancelStream(BigInt.from(streamId));
      
      final txParams = {
        'to': Web3Service.contractAddress,
        'from': widget.connectedAddress,
        'data': payload,
      }.jsify();

      final txArgs = RequestArguments(method: 'eth_sendTransaction'.toJS, params: [txParams].jsify());
      final result = await widget.provider.request(txArgs).toDart;
      final txHash = (result as JSString).toDart;
      debugPrint("🔥 TRACE: Cancellation Successful. Hash: $txHash");

      setState(() { _txStatusMessage = "Processing cancellation..."; });
      await Future.delayed(const Duration(seconds: 3));
      _fetchMyStreams();

    } catch (e) {
      debugPrint("🔥 TRACE: Cancel Failed: $e");
    } finally {
      setState(() { _isTransacting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        autofocus: true,
        focusNode: _focusNode,
        onKeyEvent: _handleKeyEvent, 
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Container(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildNavButton("Create Stream", 0),
                        _buildNavButton("My Streams", 1), 
                      ],
                    ),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: _selectedIndex == 0 
                        ? _buildCreateStreamForm() 
                        : (_isTransacting ? _buildGlobalLoadingState() : _buildActiveStreamsView()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(String title, int index) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        if (index == 1) {
          _fetchMyStreams();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE6007A) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.grey[500],
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalLoadingState() {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFFE6007A)),
          const SizedBox(height: 24),
          Text(_txStatusMessage, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildCreateStreamForm() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Deploy Capital", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Text("Lock tokens and stream them linearly over time.", style: TextStyle(color: Colors.grey[400])),
          const SizedBox(height: 32),
          
          _buildInputField("Recipient Wallet Address", _recipientCtrl, Icons.person_outline),
          const SizedBox(height: 16),
          
          DropdownButtonFormField<String>(
            value: _selectedToken,
            dropdownColor: const Color(0xFF1E293B),
            decoration: InputDecoration(
              labelText: "Select Asset",
              labelStyle: TextStyle(color: Colors.grey[500]),
              prefixIcon: Icon(Icons.token, color: Colors.grey[500]),
              filled: true,
              fillColor: Colors.black12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            items: _precompiles.keys.map((String key) {
              return DropdownMenuItem<String>(
                value: key,
                child: Text(key, style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedToken = newValue!;
              });
            },
          ),
          
          if (_selectedToken == "Custom ERC20") ...[
            const SizedBox(height: 16),
            _buildInputField("Custom Precompile Hex Address", _customAssetCtrl, Icons.code).animate().fadeIn().slideY(begin: -0.2),
          ],

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildInputField("Total Amount", _amountCtrl, Icons.attach_money, isNumber: true)),
              const SizedBox(width: 16),
              Expanded(child: _buildInputField("Duration (Days)", _durationDaysCtrl, Icons.calendar_today, isNumber: true)),
            ],
          ),
          
          const SizedBox(height: 48),

          if (_txHash != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, color: Colors.greenAccent, size: 32),
                  const SizedBox(height: 8),
                  const Text("Stream Initiated!", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(_txHash!, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_lastCreatedStreamId != null)
                    ElevatedButton.icon(
                      onPressed: () => _copyViralLink(_lastCreatedStreamId!, _recipientCtrl.text),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text("Share link with recipient", style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                ],
              ),
            ).animate().fadeIn(),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _resetForm,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("Create Another Stream", style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ).animate().fadeIn(delay: 200.ms),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isTransacting ? null : _createStream,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE6007A),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isTransacting 
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                        const SizedBox(width: 16),
                        Text(_txStatusMessage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    )
                  : const Text("Initialize Stream", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ]
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0);
  }

  Widget _buildInputField(String label, TextEditingController controller, IconData icon, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: Colors.grey[500]),
        filled: true,
        fillColor: Colors.black12,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE6007A))),
      ),
    );
  }

  Widget _buildActiveStreamsView() {
    if (_isLoadingStreams) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48.0),
          child: CircularProgressIndicator(color: Color(0xFFE6007A)),
        ),
      );
    }

    if (_txHash != null) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), borderRadius: BorderRadius.circular(24)),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 64),
            const SizedBox(height: 16),
            const Text("Action Completed", style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_txHash!, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _fetchMyStreams(), 
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE6007A), padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
              child: const Text("View Updated Streams", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ).animate().fadeIn();
    }

    if (_myStreams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Text("No streams found in history.", style: TextStyle(color: Colors.grey[500], fontSize: 18)),
        ),
      );
    }

    return Column(
      children: _myStreams.map((stream) => Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: _buildDynamicStreamCard(stream),
      )).toList(),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0);
  }

  Widget _buildDynamicStreamCard(StreamData stream) {
    String tokenSymbol = "Token";
    if (stream.asset == "0x0000000000000000000000000000000000000000") tokenSymbol = "PAS";
    if (stream.asset == "0x0000000000000000000000000000000001200001") tokenSymbol = "USDT";
    if (stream.asset == "0x0000000000000000000000000000000001200002") tokenSymbol = "USDC";

    double depositFormatted = stream.deposit / BigInt.from(10).pow(18);
    double withdrawnFormatted = stream.withdrawnAmount / BigInt.from(10).pow(18);

    bool isReceiving = stream.recipient == widget.connectedAddress.toLowerCase();
    String displayAddress = isReceiving ? stream.sender : stream.recipient;
    String addressLabel = isReceiving ? "Streaming from (Employer):" : "Streaming to (Employee):";
    
    final currentTimestampSec = (DateTime.now().millisecondsSinceEpoch / 1000).round();
    bool isDead = stream.remainingBalance == BigInt.zero;
    bool isCancelled = isDead && currentTimestampSec < stream.stopTime;
    
    Color roleColor = isDead 
        ? Colors.white24 
        : (isReceiving ? Colors.greenAccent : const Color(0xFF3B82F6));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDead ? Colors.black26 : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDead ? Colors.white10 : roleColor.withOpacity(0.3), width: 2), 
      ),
      child: StreamBuilder<int>(
        stream: Stream.periodic(const Duration(milliseconds: 50), (i) => i),
        builder: (context, snapshot) {
          final currentMs = DateTime.now().millisecondsSinceEpoch;
          final startMs = stream.startTime * 1000;
          final stopMs = stream.stopTime * 1000;
          
          double progress = 0.0;
          if (currentMs >= stopMs) {
            progress = 1.0;
          } else if (currentMs > startMs) {
            progress = (currentMs - startMs) / (stopMs - startMs);
          }
          
          if (isCancelled) {
             progress = withdrawnFormatted / depositFormatted;
          }

          double unlockedTokens = depositFormatted * progress;
          double fiatValue = unlockedTokens * (_usdPrices[tokenSymbol] ?? 1.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(addressLabel, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      const SizedBox(height: 4),
                      Text("${displayAddress.substring(0,6)}...${displayAddress.substring(displayAddress.length - 4)}", 
                        style: TextStyle(color: isDead ? Colors.white54 : Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.link, color: Colors.grey, size: 20),
                        tooltip: "Copy Pay Stub Link",
                        onPressed: () => _copyViralLink(stream.id, stream.recipient),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDead ? Colors.grey.withOpacity(0.1) : roleColor.withOpacity(0.1), 
                          borderRadius: BorderRadius.circular(20)
                        ),
                        child: Text(
                          isCancelled ? "STREAM CANCELLED" 
                          : (isDead ? "SETTLED" : (isReceiving ? "EARNING" : "FUNDING")), 
                          style: TextStyle(
                            color: isDead ? Colors.grey : roleColor, 
                            fontSize: 12, 
                            fontWeight: FontWeight.bold
                          )
                        ),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isCancelled ? "Final Unlocked Balance:" : "Live Unlocked Balance:", style: TextStyle(color: isDead ? Colors.white54 : Colors.white, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("~\$${fiatValue.toStringAsFixed(2)} USD", style: TextStyle(color: isDead ? Colors.white24 : Colors.greenAccent, fontSize: 14)),
                    ],
                  ),
                  Text("${unlockedTokens.toStringAsFixed(6)} $tokenSymbol", style: TextStyle(color: isDead ? Colors.white54 : Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: Colors.black26,
                  valueColor: AlwaysStoppedAnimation<Color>(isDead ? Colors.grey.withOpacity(0.5) : const Color(0xFFE6007A)),
                ),
              ),
              
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Total: ${depositFormatted.toStringAsFixed(2)} $tokenSymbol", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  Text("Withdrawn: ${withdrawnFormatted.toStringAsFixed(2)} $tokenSymbol", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
              
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (!isDead && isReceiving) ? () => _withdrawStream(stream.id) : null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: (!isDead && isReceiving) ? const Color(0xFF3B82F6) : Colors.white10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text("Withdraw", style: TextStyle(color: (!isDead && isReceiving) ? const Color(0xFF3B82F6) : Colors.white24, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: (!isDead && !isReceiving) ? () => _cancelStream(stream.id) : null,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: (!isDead && !isReceiving) ? Colors.redAccent.withOpacity(0.5) : Colors.white10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text("Cancel Stream", style: TextStyle(color: (!isDead && !isReceiving) ? Colors.redAccent : Colors.white24, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          );
        }
      ),
    );
  }
}