import 'package:flutter/material.dart';
import 'package:flutter_app/src/file/FileStore.dart';
import 'package:flutter_app/ui/other/ListViewAnimator.dart';
import 'package:page_transition/page_transition.dart';
import 'package:random_color/random_color.dart';

import 'FileViewer/FileViewerPage.dart';

class OtherScreen extends StatefulWidget {
  @override
  _OtherScreen createState() => _OtherScreen();
}

enum onListViewPress { Score, FileViewer }

class _OtherScreen extends State<OtherScreen> {
  final List<Map> listViewData = [
    {"icon": Icons.search, "title": "分數查詢", "onPress": onListViewPress.Score},
    {"icon": Icons.file_download, "title": "下載檔案", "onPress": onListViewPress.FileViewer},
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () async {

    });
  }

  void _onListViewPress(onListViewPress value) {
    switch (value) {
      case onListViewPress.FileViewer:
        FileStore.findLocalPath(context).then( (filePath) {
          Navigator.push(
            context,
            PageTransition(
              type: PageTransitionType.leftToRight,
              child: FileViewerPage(
                title: "FileViewer",
                path: filePath,
              ),
            ),
          );
        });
        break;
      default:
        break;
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Other'),
      ),
      body: ListView.separated(
        itemCount: listViewData.length,
        itemBuilder: (context, index) {
          Widget widget;
          widget = _buildOther( listViewData[index] );
          return GestureDetector(
              behavior: HitTestBehavior.opaque, //讓透明部分有反應
              child: WidgetANimator(widget),
              onTap: () {
                if (index != 0)
                  _onListViewPress(listViewData[index]['onPress']);
              });
        },
        separatorBuilder: (context, index) {
          // 顯示格線
          return Container(
            color: Colors.black12,
            height: 1,
          );
        },
      ),
    );
  }


  Container _buildOther(Map data) {
    return Container(
      //color: Colors.yellow,
      padding:
      EdgeInsets.only(top: 20.0, left: 20.0, right: 20.0, bottom: 20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            data['icon'],
            color: RandomColor()
                .randomColor(colorSaturation: ColorSaturation.highSaturation),
          ),
          SizedBox(
            width: 20.0,
          ),
          Text(
            data['title'],
            style: TextStyle(fontSize: 18),
          ),
        ],
      ),
    );
  }

}
