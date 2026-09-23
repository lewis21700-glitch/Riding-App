import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const api = 'http://10.0.2.2:3000';

void main() => runApp(const RideApp());

class RideApp extends StatelessWidget {
  const RideApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'RideApp',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
    home: const LoginPage(),
  );
}

class Api {
  static Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await http.post(Uri.parse('$api/api/login'), headers: {'Content-Type':'application/json'}, body: jsonEncode({'email':email,'password':password}));
    final d = jsonDecode(r.body);
    if (r.statusCode >= 400) throw Exception(d['error'] ?? 'Login failed');
    return Map<String,dynamic>.from(d);
  }
  static Future<Map<String, dynamic>> request(String path, String token, {String method='GET', Map<String,dynamic>? body}) async {
    final headers={'Content-Type':'application/json','Authorization':'Bearer $token'};
    late http.Response r;
    final u=Uri.parse('$api$path');
    if(method=='POST') r=await http.post(u,headers:headers,body:jsonEncode(body??{}));
    else r=await http.get(u,headers:headers);
    final d=jsonDecode(r.body);
    if(r.statusCode>=400) throw Exception(d['error'] ?? 'Request failed');
    return Map<String,dynamic>.from(d);
  }
  static Future<List<dynamic>> list(String path,String token) async {
    final r=await http.get(Uri.parse('$api$path'),headers:{'Authorization':'Bearer $token'});
    final d=jsonDecode(r.body); if(r.statusCode>=400) throw Exception(d['error']??'Request failed'); return List<dynamic>.from(d);
  }
}

class LoginPage extends StatefulWidget { const LoginPage({super.key}); @override State<LoginPage> createState()=>_LoginPageState(); }
class _LoginPageState extends State<LoginPage>{
  final email=TextEditingController(); final password=TextEditingController(); bool busy=false;
  Future<void> login() async { if(email.text.isEmpty||password.text.isEmpty)return; setState(()=>busy=true); try{final d=await Api.login(email.text.trim(),password.text); if(d['user']['role']!='rider')throw Exception('Please use a rider account.'); final p=await SharedPreferences.getInstance(); await p.setString('token',d['token']); await p.setString('user',jsonEncode(d['user'])); if(mounted)Navigator.pushReplacement(context,MaterialPageRoute(builder:(_)=>HomePage(token:d['token'],user:Map<String,dynamic>.from(d['user']))));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext c)=>Scaffold(body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:420),child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('🚕',style:TextStyle(fontSize:54)),const SizedBox(height:8),const Text('RideApp',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),const SizedBox(height:28),TextField(controller:email,decoration:const InputDecoration(labelText:'Email',border:OutlineInputBorder())),const SizedBox(height:14),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),const SizedBox(height:18),SizedBox(width:double.infinity,height:50,child:FilledButton(onPressed:busy?null:login,child:Text(busy?'Signing in...':'Sign in')))]))));
}

class HomePage extends StatefulWidget{final String token;final Map<String,dynamic> user;const HomePage({super.key,required this.token,required this.user});@override State<HomePage> createState()=>_HomePageState();}
class _HomePageState extends State<HomePage>{
  int tab=0; Position? pos; String rideType='Car'; final pickup=TextEditingController(); final destination=TextEditingController(); final distance=TextEditingController(); double? fare; bool estimating=false,booking=false; List<dynamic> rides=[];
  final types=['Car','Tuk Tuk','Motorbike','Direct Ride'];
  Future<void> currentLocation() async { try{var enabled=await Geolocator.isLocationServiceEnabled();if(!enabled)throw Exception('Please turn on location services.');var permission=await Geolocator.checkPermission();if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();if(permission==LocationPermission.denied||permission==LocationPermission.deniedForever)throw Exception('Location permission is required.');final p=await Geolocator.getCurrentPosition();setState((){pos=p;pickup.text='Current location (${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)})';});}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}}
  Future<void> estimate() async {if(pickup.text.trim().isEmpty||(rideType!='Direct Ride'&&destination.text.trim().isEmpty)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter pickup and destination first.')));return;}if(rideType=='Direct Ride'){setState(()=>fare=null);return;}final d=double.tryParse(distance.text.trim());if(d==null||d<0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter estimated distance in km.')));return;}setState(()=>estimating=true);try{final r=await http.post(Uri.parse('$api/api/fare/estimate'),headers:{'Content-Type':'application/json','Authorization':'Bearer ${widget.token}'},body:jsonEncode({'ride_type':rideType,'distance_km':d}));final data=jsonDecode(r.body);if(r.statusCode>=400)throw Exception(data['error']??'Fare error');setState(()=>fare=(data['estimated_fare'] as num).toDouble());}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}finally{if(mounted)setState(()=>estimating=false);}}
  Future<void> book() async {if(pickup.text.trim().isEmpty||(rideType!='Direct Ride'&&destination.text.trim().isEmpty)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Please complete pickup and destination.')));return;}if(rideType!='Direct Ride'&&fare==null){await estimate();if(fare==null)return;}setState(()=>booking=true);try{final body={'ride_type':rideType,'pickup_location':pickup.text.trim(),'destination':destination.text.trim(),'distance_km':double.tryParse(distance.text),'pickup_lat':pos?.latitude,'pickup_lng':pos?.longitude};final r=await http.post(Uri.parse('$api/api/rides'),headers:{'Content-Type':'application/json','Authorization':'Bearer ${widget.token}'},body:jsonEncode(body));final d=jsonDecode(r.body);if(r.statusCode>=400)throw Exception(d['error']??'Booking failed');if(mounted)showDialog(context:context,builder:(_)=>AlertDialog(title:const Text('Ride requested'),content:Text('Ride #${d['ride_id']}\n${d['direct']==true?'Final fare will be calculated after the ride.':'Estimated fare: \$${NumberFmt(d['estimated_fare'])}'}'),actions:[TextButton(onPressed:(){Navigator.pop(context);loadRides();},child:const Text('OK'))]));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ',''))));}finally{if(mounted)setState(()=>booking=false);}}
  Future<void> loadRides() async {try{final r=await Api.list('/api/my-rides',widget.token);setState(()=>rides=r);}catch(e){}}
  @override void initState(){super.initState();loadRides();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('RideApp'),actions:[IconButton(onPressed:loadRides,icon:const Icon(Icons.refresh))]),body:tab==0?bookingView():historyView(),bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const[NavigationDestination(icon:Icon(Icons.local_taxi),label:'Book'),NavigationDestination(icon:Icon(Icons.history),label:'Rides') ]));
  Widget bookingView()=>ListView(padding:const EdgeInsets.all(18),children:[Text('Hello, ${widget.user['name'] ?? 'Rider'}',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:18),DropdownButtonFormField<String>(value:rideType,decoration:const InputDecoration(labelText:'Ride type',border:OutlineInputBorder()),items:types.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){ if(v != null) setState(() { rideType=v; fare=null; }); }),const SizedBox(height:14),TextField(controller:pickup,decoration:InputDecoration(labelText:'Pickup location',border:const OutlineInputBorder(),suffixIcon:IconButton(onPressed:currentLocation,icon:const Icon(Icons.my_location)))),const SizedBox(height:14),if(rideType!='Direct Ride')... [TextField(controller:destination,decoration:const InputDecoration(labelText:'Destination',border:OutlineInputBorder())),const SizedBox(height:14),TextField(controller:distance,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Estimated distance (km)',border:OutlineInputBorder())),const SizedBox(height:12),OutlinedButton.icon(onPressed:estimating?null:estimate,icon:const Icon(Icons.calculate),label:Text(estimating?'Calculating...':'Calculate fare')),],if(rideType=='Direct Ride')const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('Direct Ride: no destination required. Final fare is set by the driver when the ride is completed.'))),if(fare!=null)Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[const Text('Estimated Fare'),Text('\$${NumberFmt(fare)}',style:const TextStyle(fontSize:34,fontWeight:FontWeight.bold))]))),const SizedBox(height:12),SizedBox(height:52,child:FilledButton.icon(onPressed:booking?null:book,icon:const Icon(Icons.local_taxi),label:Text(booking?'Requesting...':'Request Ride')))]);
  Widget historyView()=>ListView(padding:const EdgeInsets.all(18),children:[Text('My Rides',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:12),if(rides.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(24),child:Text('No rides yet.'))),...rides.map((r)=>Card(child:ListTile(title:Text('Ride #${r['id']} • ${r['ride_type']}'),subtitle:Text('${r['pickup_location']} → ${r['destination']?.toString().isEmpty==true?'No destination':r['destination']}\nStatus: ${r['status']}'),trailing:Text(r['fare']==null?'—':'\$${NumberFmt(r['fare'])}'))))]);
}
String NumberFmt(dynamic n)=> (double.tryParse((n ?? 0).toString()) ?? 0).toStringAsFixed(2);
