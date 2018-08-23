import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity/connectivity.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_database/firebase_database.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';


final googleSignIn = new GoogleSignIn(
  scopes: [
    'email',
    'profile',
  ],
);
final auth = FirebaseAuth.instance;
final reference = FirebaseDatabase.instance.reference().child('photo');

var rng = new Random();

FirebaseUser currentFirebaseUser;

void main() {
  runApp(new NonInstantGalleryApp());
}

Future<Null> _ensureLoggedIn() async {
  try {
    if (await auth.currentUser() == null) {
      GoogleSignInAccount user = googleSignIn.currentUser;
      if (user == null) user = await googleSignIn.signInSilently();
      if (user == null) {
        await googleSignIn.signIn();
      }
      GoogleSignInAuthentication credentials =
      await googleSignIn.currentUser.authentication;
      await auth.signInWithGoogle(
        idToken: credentials.idToken,
        accessToken: credentials.accessToken,
      );
    }

    currentFirebaseUser = await auth.currentUser();
  } catch (e) {
  }
}

Future<String> _localFileName(String basename) async {
  Directory photosDir = await getTemporaryDirectory();
  return '${photosDir.path}/$basename';
}

Future<File> cache(String url) async {
  var file = new File(await _localFileName(Uri.parse(url).pathSegments.last));
  if (await file.exists()) {
    return file;
  }

  final connectivityResult = await (new Connectivity().checkConnectivity());
  if (connectivityResult == ConnectivityResult.none) {
    // Don't try to fetch from cache if there's no Internet.
    return null;
  }

  await _ensureLoggedIn();
  final response = await http.get(url);
  if (response.statusCode != 200) {
    print('HTTP error: ${response.statusCode}');
    print(response.body);
    return null;
  }

  await file.writeAsBytes(response.bodyBytes);
  return file;
}


class NonInstantGalleryApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: "Uncanny Gallery",
      theme: new ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: new Gallery(),
    );
  }
}

@override
class UncannyImage extends StatelessWidget {
  UncannyImage({this.snapshot, this.animation});
  BuildContext _context;
  final DataSnapshot snapshot;
  final Animation animation;

  Widget build(BuildContext context) {
    _context = context;
    return new SizeTransition(
      sizeFactor: new CurvedAnimation(
          parent: animation, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: new Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            new GestureDetector(
              onTap: () {
                _share(snapshot.value['file']);
              }, child: _image(snapshot.value['file']),
            )
          ],
        ),
      ),
    );
  }

  Widget _image(String url) {
    if(localFiles.containsKey(url) && localFiles[url] != null) {
      return new Image.file(localFiles[url], width: 200.0);
    }
    return new Text(url);
  }

  _share(String url) {
    if (url != null && localFiles.containsKey(url) && localFiles[url] != null) {
      try {
        final channel = const MethodChannel(
            'channel:au.id.martinstrauss.noninstantgallery.share/share');
        channel.invokeMethod('shareFile', basename(url));
      } catch (e) {
        error('shareImage: $e');
      }
    }
  }

  void error(String message) {
    message = 'ERROR: $message';
    print(message);
    if (_context != null) {
      Scaffold
          .of(_context)
          .showSnackBar(new SnackBar(content: new Text(message)));
    }
  }
}

class Gallery extends StatefulWidget {
  @override
  State createState() => new GalleryState();
}

Map<String, File> localFiles = new Map();

class GalleryState extends State<Gallery> {
  BuildContext _context;

  StreamSubscription<Event> _dbSubscription;

  @override
  void initState() {
    super.initState();

    _setUpDbSubscription();
  }

  void _setUpDbSubscription() async {
    await _ensureLoggedIn();
    localFiles.clear();

    _dbSubscription = reference.onValue.listen((Event event) async {
      if (event.snapshot.value != null) {
        event.snapshot.value.forEach((key, value) async {
          String url = value['file'];
          localFiles[url] = await cache(url);
        });
      }
    }, onError: (Object o) {
      final DatabaseError error = o;
      print('DatabaseError: ${error.code} ${error.message}');
    });
  }

  dispose() {
    _dbSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
        appBar: new AppBar(
          title: new Text("Uncanny Camera Photos"),
          elevation: Theme.of(context).platform == TargetPlatform.iOS ? 0.0 : 4.0,
        ),
        body: new Builder(builder: (BuildContext context) {
          _context = context;
          return new Center(child: _animatedList());
        }),
    );
  }

  Widget _animatedList() {
    return new Column(children: <Widget>[
      new Flexible(
        child: new FirebaseAnimatedList(
          query: reference,
          sort: (a, b) => b.key.compareTo(a.key),
          padding: new EdgeInsets.all(8.0),
          reverse: true,
          itemBuilder: (_1, DataSnapshot snapshot, Animation<double> animation, _2) {
            return new UncannyImage(
                snapshot: snapshot,
                animation: animation
            );
          },
        ),
      ),
      new FloatingActionButton(
        child: const Icon(Icons.refresh),
        onPressed: () {
          setState(() {
            if (_dbSubscription != null) _dbSubscription.cancel();
            _setUpDbSubscription();
          });
        },
      ),
    ]);
  }

  void error(String message) {
    message = 'ERROR: $message';
    print(message);
    if (_context != null) {
      Scaffold
          .of(_context)
          .showSnackBar(new SnackBar(content: new Text(message)));
    }
  }
}
