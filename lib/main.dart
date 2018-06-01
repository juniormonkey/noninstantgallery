import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:connectivity/connectivity.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/ui/firebase_animated_list.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    print('_ensureLoggedIn: $e');
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
  final DataSnapshot snapshot;
  final Animation animation;

  Widget build(BuildContext context) {
    return new SizeTransition(
      sizeFactor: new CurvedAnimation(
          parent: animation, curve: Curves.easeOut),
      axisAlignment: 0.0,
      child: new Container(
        margin: const EdgeInsets.symmetric(vertical: 10.0),
        child: new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            new Image.network(snapshot.value['file'], height: 250.0),
          ],
        ),
      ),
    );
  }
}

class Gallery extends StatefulWidget {
  @override
  State createState() => new GalleryState();
}

class GalleryState extends State<Gallery> {
  static const int MAX_PRIORITY = 10000;

  BuildContext _context;

/*
  StreamSubscription<Event> _dbSubscription;
  StreamSubscription<ConnectivityResult> _connectivitySubscription;

  Queue<String> uploadQueue = new Queue();

  @override
  void initState() {
    super.initState();

    _dbSubscription = reference.onValue.listen((Event event) async {
      if (event.snapshot.value != null) {
        event.snapshot.value.forEach((key, value) async {
          await cache(value['file']);
        });
      }
    }, onError: (Object o) {
      final DatabaseError error = o;
      print('DatabaseError: ${error.code} ${error.message}');
    });

    _connectivitySubscription = new Connectivity()
        .onConnectivityChanged
        .listen((ConnectivityResult result) async {
      if (result == ConnectivityResult.none) {
        // Don't try to upload if there's no Internet.
        return;
      }
      if (uploadQueue.length == 0) {
        // Don't try to remove anything if the queue is empty.
        return;
      }
      var filename;
      while (filename = uploadQueue.removeFirst() != null) {
        await _upload(filename);
      }
    });
  }

  dispose() {
    _dbSubscription.cancel();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  _upload(String filename) async {
    await _ensureLoggedIn();

    File imageFile = new File(filename);
    StorageReference ref =
    FirebaseStorage.instance.ref().child(basename(imageFile.path));
    StorageUploadTask uploadTask = ref.putFile(imageFile);
    try {
      Uri downloadUrl = (await uploadTask.future).downloadUrl;

      int priority = rng.nextInt(MAX_PRIORITY);
      reference.push().set({
        'file': downloadUrl.toString(),
        'senderId': currentFirebaseUser.uid,
        'senderEmail': currentFirebaseUser.email,
      }, priority: priority);
    } catch (e) {
      error('_upload: $e');
      uploadQueue.add(filename);
    }
  }
  */

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
    ]);
  }

  void notify(String message) {
    print(message);
    if (_context != null) {
      Scaffold
          .of(_context)
          .showSnackBar(new SnackBar(content: new Text(message)));
    }
  }

  void error(String message) {
    message = 'ERROR: $message';
    setState(() {
 //     _placeholderText = message;
    });
    notify(message);
  }
}
