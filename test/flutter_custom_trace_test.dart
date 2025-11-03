import 'dart:convert';

// import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_custom_trace/flutter_custom_trace.dart';

void main() {
  try{
    CustomTrace programInfo = CustomTrace(StackTrace.current);
    Map dataError = {
      'file': '${programInfo.fileName},line: ${programInfo.lineNumber}',
      'message': "message",
      'date': programInfo.orangeDateTime()
    };
    var jsonError = jsonEncode(dataError);
    programInfo.saveError(jsonError: jsonError);
    print("SUCCESS");
  }catch(_){
    print("ERROR");
  }
}
