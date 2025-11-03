import 'package:shared_preferences/shared_preferences.dart';

class CustomTrace {
  final StackTrace _trace;

  String? fileName;
  int? lineNumber;
  int? columnNumber;
  // List<String> listDebugInfo = [];

  CustomTrace(this._trace) {
    _parseTrace();
  }

  void _parseTrace() {
    var traceString = _trace.toString().split('\n')[0]; // Get the first line of the stack trace
    var indexOfFileName = traceString.indexOf(RegExp(r'[A-Za-z_]+\.dart'));
    var fileInfo = traceString.substring(indexOfFileName);
    var listOfInfos = fileInfo.split(':');
    
    fileName = listOfInfos[0];
    lineNumber = int.parse(listOfInfos[1]);
    columnNumber = int.parse(listOfInfos[2].replaceAll(')', ''));
  }

  void saveError({required String jsonError}) async {
    final prefs = await SharedPreferences.getInstance();
    final bool? isDebug = prefs.getBool('is_debug');
    if(isDebug != null){
      if(isDebug){
        final List<String>? listError = prefs.getStringList('debug_info');
        if(listError != null){
          if(listError.isNotEmpty){
            List<String> list = [];
            for(var rec in listError){
              list.add(rec);
            }
            list.add(jsonError);
            prefs.setStringList('debug_info', list);
          }else{
            List<String> list = [];
            list.add(jsonError);
            prefs.setStringList('debug_info', list);
          }
        }else{
          List<String> list = [];
          list.add(jsonError);
          prefs.setStringList('debug_info', list);
        }
      }
    }
  }
  String orangeDateTime() {
    var date = DateTime.now();
    String day = '';
    if(date.day.toString().length > 1){
      day = date.day.toString();
    }else{
      day = '0${date.day.toString()}';
    }
    var myDate =
        '$day/${date.month}/${date.year} ${date.hour}:${date.minute}:${date.second}';

    return myDate;
  }

  
}



