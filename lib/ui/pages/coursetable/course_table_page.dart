// TODO: remove sdk version selector after migrating to null-safety.
// @dart=2.10
import 'dart:io';
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:eva_icons_flutter/eva_icons_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/debug/log/log.dart';
import 'package:flutter_app/src/config/app_config.dart';
import 'package:flutter_app/src/model/course/course_class_json.dart';
import 'package:flutter_app/src/model/coursetable/course_table_json.dart';
import 'package:flutter_app/src/model/userdata/user_data_json.dart';
import 'package:flutter_app/src/r.dart';
import 'package:flutter_app/src/store/local_storage.dart';
import 'package:flutter_app/src/task/course/course_semester_task.dart';
import 'package:flutter_app/src/task/course/course_table_task.dart';
import 'package:flutter_app/src/task/iplus/iplus_subscribe_notice_task.dart';
import 'package:flutter_app/src/task/task_flow.dart';
import 'package:flutter_app/ui/other/my_toast.dart';
import 'package:flutter_app/ui/other/route_utils.dart';
import 'package:flutter_app/ui/pages/coursetable/course_table_control.dart';
import 'package:flutter_app/ui/pages/coursetable/over_repaint_boundary.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sprintf/sprintf.dart';

class CourseTablePage extends StatefulWidget {
  const CourseTablePage({Key key}) : super(key: key);

  @override
  State<CourseTablePage> createState() => _CourseTablePageState();
}

class _CourseTablePageState extends State<CourseTablePage> {
  final TextEditingController _studentIdControl = TextEditingController();
  final FocusNode _studentFocus = FocusNode();
  final GlobalKey _key = GlobalKey();
  bool isLoading = true;
  CourseTableJson courseTableData;
  static double dayHeight = 25;
  static double studentIdHeight = 40;
  static double courseHeight = 60;
  static double sectionWidth = 20;
  static int courseTableWithAlpha = 0x44;
  static int showCourseTableNum = 9;
  CourseTableControl courseTableControl = CourseTableControl();
  bool favorite = false;
  bool loadCourseNotice = true;

  @override
  void initState() {
    super.initState();
    _studentIdControl.text = " ";
    Future.microtask(() => _loadLocalSettings());
  }

  void getCourseNotice() async {
    setState(() {
      loadCourseNotice = false;
    });
    if (!LocalStorage.instance.getOtherSetting().checkIPlusNew) {
      return;
    }
    if (!LocalStorage.instance.getFirstUse(LocalStorage.courseNotice, timeOut: 15 * 60)) {
      return;
    }
    if (LocalStorage.instance.getAccount() != LocalStorage.instance.getCourseSetting().info.studentId) {
      //只有顯示自己的課表時才會檢查新公告
      return;
    }
    setState(() {
      loadCourseNotice = true;
    });

    TaskFlow taskFlow = TaskFlow();
    var task = IPlusSubscribeNoticeTask();
    task.openLoadingDialog = false;
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      List<String> v = task.result;
      List<String> value = [];
      v = v ?? [];
      for (int i = 0; i < v.length; i++) {
        String courseName = v[i];
        CourseInfoJson courseInfo = courseTableData.getCourseInfoByCourseName(courseName);
        if (courseInfo != null) {
          value.add(courseName);
        }
      }
      if (value != null && value.isNotEmpty) {
        Get.dialog(
          AlertDialog(
            title: Text(R.current.findNewMessage),
            content: SizedBox(
              width: double.minPositive,
              child: ListView.builder(
                itemCount: value.length,
                shrinkWrap: true, //使清單最小化
                itemBuilder: (BuildContext context, int index) {
                  return TextButton(
                    child: Text(value[index]),
                    onPressed: () {
                      String courseName = value[index];
                      CourseInfoJson courseInfo = courseTableData.getCourseInfoByCourseName(courseName);
                      if (courseInfo != null) {
                        _showCourseDetail(courseInfo);
                      } else {
                        MyToast.show(R.current.noSupport);
                        Get.back();
                      }
                    },
                  );
                },
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text(R.current.sure),
                onPressed: () {
                  Get.back();
                },
              ),
            ],
          ),
          barrierDismissible: true,
        );
      }
    }
    LocalStorage.instance.setAlreadyUse(LocalStorage.courseNotice);
    setState(() {
      loadCourseNotice = false;
    });
  }

  @override
  void setState(fn) {
    if (mounted && context != null) {
      super.setState(fn);
    }
  }

  @override
  void dispose() {
    _studentFocus.dispose();
    super.dispose();
  }

  void _loadLocalSettings() {
    final renderObject = _key.currentContext.findRenderObject();
    courseHeight = (renderObject.semanticBounds.size.height - studentIdHeight - dayHeight) / showCourseTableNum;
    final courseTable = LocalStorage.instance.getCourseSetting().info;
    if (courseTable == null || courseTable.isEmpty) {
      _getCourseTable(studentId: courseTable.studentId, semesterSetting: courseTable.courseSemester);
    } else {
      _showCourseTable(courseTable);
    }
  }

  Future<void> _getSemesterList(String studentId) async {
    final taskFlow = TaskFlow();
    final task = CourseSemesterTask(studentId);
    taskFlow.addTask(task);
    if (await taskFlow.start()) {
      LocalStorage.instance.setSemesterJsonList(task.result);
    }
  }

  void _getCourseTable({SemesterJson semesterSetting, String studentId, bool refresh = false}) async {
    await Future.delayed(const Duration(microseconds: 100)); //等待頁面刷新
    UserDataJson userData = LocalStorage.instance.getUserData();
    studentId = studentId?.trim() ?? '';
    studentId = (studentId.isEmpty ? null : studentId) ?? userData.account;
    if (courseTableData?.studentId != studentId) {
      LocalStorage.instance.clearSemesterJsonList(); //需重設因為更換了studentId
    }
    SemesterJson semesterJson;
    if (semesterSetting == null || semesterSetting.semester.isEmpty || semesterSetting.year.isEmpty) {
      await _getSemesterList(studentId);
      semesterJson = LocalStorage.instance.getSemesterJsonItem(0);
    } else {
      semesterJson = semesterSetting;
    }
    if (semesterJson == null) {
      return;
    }

    CourseTableJson courseTable;
    if (!refresh) {
      courseTable = LocalStorage.instance.getCourseTable(studentId, semesterSetting); //去取找是否已經暫存
    }
    if (courseTable == null) {
      TaskFlow taskFlow = TaskFlow();
      var task = CourseTableTask(studentId, semesterJson);
      taskFlow.addTask(task);
      if (await taskFlow.start()) {
        courseTable = task.result;
      }
    }

    if (courseTable != null) {
      LocalStorage.instance.getCourseSetting().info = courseTable;
      LocalStorage.instance.saveCourseSetting();
      _showCourseTable(courseTable);
    }
  }

  Widget _getSemesterItem(SemesterJson semester) {
    final semesterString = "${semester.year}-${semester.semester}";
    return TextButton(
      child: Text(semesterString),
      onPressed: () {
        Get.back();
        _getCourseTable(semesterSetting: semester, studentId: _studentIdControl.text); //取得課表
      },
    );
  }

  void _showSemesterList() async {
    _unFocusStudentInput();
    if (LocalStorage.instance.getSemesterList()?.isEmpty == true) {
      final taskFlow = TaskFlow();
      final task = CourseSemesterTask(_studentIdControl.text);
      taskFlow.addTask(task);
      if (await taskFlow.start()) {
        LocalStorage.instance.setSemesterJsonList(task.result);
      }
    }

    final List<SemesterJson> semesterList = LocalStorage.instance.getSemesterList();

    if (semesterList?.isEmpty ?? true) {
      return;
    }

    Get.dialog(
      AlertDialog(
        content: SizedBox(
          width: double.minPositive,
          child: ListView.builder(
            itemCount: semesterList?.length ?? 0,
            shrinkWrap: true,
            itemBuilder: (context, index) => _getSemesterItem(semesterList[index]),
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  _onPopupMenuSelect(int value) {
    switch (value) {
      case 0:
        final credit = courseTableData?.getTotalCredit()?.toString();
        if (credit != null) {
          MyToast.show(sprintf("%s:%s", [R.current.credit, credit]));
        }
        break;
      case 1:
        _loadFavorite();
        break;
      case 2:
        screenshot();
        break;
      default:
        break;
    }
  }

  void _setFavorite(bool like) {
    if (like) {
      LocalStorage.instance.addCourseTable(courseTableData);
    } else {
      LocalStorage.instance.removeCourseTable(courseTableData);
    }
    LocalStorage.instance.saveCourseTableList();
  }

  void _loadFavorite() async {
    List<CourseTableJson> value = LocalStorage.instance.getCourseTableList();
    if (value.isEmpty) {
      MyToast.show(R.current.noAnyFavorite);
      return;
    }
    Get.dialog(
      StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setState) {
          return AlertDialog(
            content: SizedBox(
              width: double.minPositive,
              child: ListView.builder(
                itemCount: value.length,
                shrinkWrap: true, //使清單最小化
                itemBuilder: (BuildContext context, int index) {
                  return Slidable(
                    startActionPane: const ActionPane(
                      motion: ScrollMotion(),
                      children: [],
                    ),
                    endActionPane: ActionPane(
                      motion: null,
                      children: [
                        SlidableAction(
                          label: R.current.delete,
                          foregroundColor: Colors.red,
                          icon: Icons.delete_forever,
                          onPressed: (_) {
                            LocalStorage.instance.removeCourseTable(value[index]);
                            value.removeAt(index);
                            LocalStorage.instance.saveCourseTableList().then((_) => setState(() {}));
                          },
                        ),
                      ],
                    ),
                    child: SizedBox(
                      height: 50,
                      child: TextButton(
                        child: Text(sprintf("%s %s %s-%s", [
                          value[index].studentId,
                          value[index].studentName,
                          value[index].courseSemester.year,
                          value[index].courseSemester.semester
                        ])),
                        onPressed: () {
                          LocalStorage.instance.getCourseSetting().info = value[index]; //儲存課表
                          LocalStorage.instance.saveCourseSetting();
                          _showCourseTable(value[index]);
                          LocalStorage.instance.clearSemesterJsonList(); //須清除已儲存學期
                          Get.back();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
      barrierDismissible: true,
    );
    setState(() {
      favorite = (LocalStorage.instance.getCourseTableList().contains(courseTableData));
    });
  }

  @override
  Widget build(BuildContext context) {
    final semesterSetting = courseTableData?.courseSemester ?? SemesterJson();
    final semesterString = "${semesterSetting.year}-${semesterSetting.semester}";

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(R.current.titleCourse),
        actions: [
          (!isLoading && loadCourseNotice)
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    backgroundColor: Theme.of(context).colorScheme.background,
                    color: Theme.of(context).colorScheme.tertiary,
                    strokeWidth: 4,
                  ),
                )
              : const SizedBox.shrink(),
          (!isLoading && LocalStorage.instance.getAccount() != courseTableData?.studentId)
              ? Padding(
                  padding: const EdgeInsets.only(
                    right: 20,
                  ),
                  child: InkWell(
                    onTap: () {
                      setState(() => favorite = !favorite);
                      _setFavorite(favorite);
                    },
                    child: Icon(Icons.favorite, color: (favorite) ? Colors.pinkAccent : Colors.white),
                  ),
                )
              : const SizedBox.shrink(),
          Padding(
            padding: const EdgeInsets.only(
              right: 20,
            ),
            child: InkWell(
              onTap: () => _getCourseTable(
                semesterSetting: courseTableData?.courseSemester,
                studentId: _studentIdControl.text,
                refresh: true,
              ),
              child: const Icon(EvaIcons.refreshOutline),
            ),
          ),
          PopupMenuButton<int>(
            onSelected: (result) => setState(() => _onPopupMenuSelect(result)),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 0,
                child: Text(R.current.searchCredit),
              ),
              PopupMenuItem(
                value: 1,
                child: Text(R.current.loadFavorite),
              ),
              if (Platform.isAndroid)
                PopupMenuItem(
                  value: 2,
                  child: Text(R.current.setAsAndroidWeight),
                ),
            ],
          )
        ],
      ),
      body: Column(
        key: _key,
        children: [
          Container(
            height: studentIdHeight,
            color: Theme.of(context).colorScheme.background,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    scrollPadding: const EdgeInsets.all(0),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(10),
                      hintText: R.current.pleaseEnterStudentId,
                    ),
                    onEditingComplete: () {
                      if (_studentIdControl.text.isEmpty) {
                        MyToast.show(R.current.pleaseEnterStudentId);
                      } else {
                        _getCourseTable(studentId: _studentIdControl.text);
                      }
                      _studentFocus.unfocus();
                    },
                    controller: _studentIdControl,
                    focusNode: _studentFocus,
                  ),
                ),
                TextButton(
                  child: Row(
                    children: [
                      Text(
                        semesterString,
                        textAlign: TextAlign.center,
                      ),
                      const Padding(
                        padding: EdgeInsets.all(5),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                  onPressed: () => _showSemesterList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildListViewWithScreenshot(),
          ),
        ],
      ),
    );
  }

  final GlobalKey<OverRepaintBoundaryState> overRepaintKey = GlobalKey();

  Widget _buildListViewWithScreenshot() => SingleChildScrollView(
        child: OverRepaintBoundary(
          key: overRepaintKey,
          child: RepaintBoundary(
            child: (isLoading)
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            //makes the red row full width
                            child: SizedBox(
                              height: courseHeight * showCourseTableNum,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    children: List.generate(
                      1 + courseTableControl.getSectionIntList.length,
                      (index) {
                        final widget = (index == 0) ? _buildDay() : _buildCourseTable(index - 1);
                        return AnimationConfiguration.staggeredList(
                          position: index,
                          duration: const Duration(milliseconds: 375),
                          child: ScaleAnimation(
                            child: FadeInAnimation(
                              child: widget,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      );

  Widget _buildDay() {
    final List<Widget> widgetList = [];
    widgetList.add(Container(
      width: sectionWidth,
    ));
    for (final i in courseTableControl.getDayIntList) {
      widgetList.add(
        Expanded(
          child: Text(
            courseTableControl.getDayString(i),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Container(
      color: Theme.of(context).colorScheme.background.withAlpha(courseTableWithAlpha),
      height: dayHeight,
      child: Row(
        children: widgetList,
      ),
    );
  }

  Widget _buildCourseTable(int index) {
    final section = courseTableControl.getSectionIntList[index];
    final color = index % 2 == 1
        ? Theme.of(context).colorScheme.surface
        : Theme.of(context).colorScheme.surfaceVariant.withAlpha(courseTableWithAlpha);
    final List<Widget> widgetList = [];
    widgetList.add(
      Container(
        width: sectionWidth,
        alignment: Alignment.center,
        child: Text(
          courseTableControl.getSectionString(section),
          textAlign: TextAlign.center,
        ),
      ),
    );

    final isDarkMode = Get.isDarkMode;

    for (final day in courseTableControl.getDayIntList) {
      final courseInfo = courseTableControl.getCourseInfo(day, section) ?? CourseInfoJson();
      final color = courseTableControl.getCourseInfoColor(day, section);
      widgetList.add(
        Expanded(
          child: (courseInfo.isEmpty)
              ? const SizedBox.shrink()
              : Card(
                  elevation: 0,
                  margin: const EdgeInsets.all(2),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                      color: color,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: const BorderRadius.all(Radius.circular(5)),
                        highlightColor: isDarkMode ? Colors.white : Colors.black12,
                        onTap: () => showCourseDetailDialog(section, courseInfo),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: AutoSizeText(
                                  courseInfo.main.course.name,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  minFontSize: 6,
                                  maxLines: 3,
                                  textAlign: TextAlign.center,
                                ),
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
    return Container(
      color: color,
      height: courseHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgetList,
      ),
    );
  }

  //顯示課程對話框
  void showCourseDetailDialog(int section, CourseInfoJson courseInfo) {
    _unFocusStudentInput();
    final course = courseInfo.main.course;
    final classroomName = courseInfo.main.getClassroomName();
    final teacherName = courseInfo.main.getTeacherName();
    final studentId = LocalStorage.instance.getCourseSetting().info.studentId;
    setState(() {
      _studentIdControl.text = studentId;
    });
    Get.dialog(
      AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(24.0, 20.0, 10.0, 10.0),
        title: Text(course.name),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              child: Text(sprintf("%s : %s", [R.current.courseId, course.id])),
              onLongPress: () async {
                course.id = await _showEditDialog(course.id);
                await LocalStorage.instance.saveOtherSetting();
                setState(() {});
              },
            ),
            Text(sprintf("%s : %s", [R.current.time, courseTableControl.getTimeString(section)])),
            Text(sprintf("%s : %s", [R.current.location, classroomName])),
            Text(sprintf("%s : %s", [R.current.instructor, teacherName])),
          ],
        ),
        actions: courseInfo.main.course.id.isNotEmpty
            ? [
                TextButton.icon(
                  onPressed: () => _showCourseDetail(courseInfo),
                  icon: const Icon(Icons.add_outlined),
                  label: Text(R.current.details),
                ),
              ]
            : [const SizedBox.shrink()],
      ),
      barrierDismissible: true,
    );
  }

  Future<String> _showEditDialog(String value) async {
    final TextEditingController controller = TextEditingController();
    controller.text = value;
    final v = await Get.dialog<String>(
      AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        title: const Text('Edit'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(hintText: value),
              ),
            )
          ],
        ),
        actions: [
          TextButton(
              child: Text(R.current.cancel),
              onPressed: () {
                Get.back(result: null);
              }),
          TextButton(
              child: Text(R.current.sure),
              onPressed: () {
                Get.back<String>(result: controller.text);
              })
        ],
      ),
      barrierDismissible: true,
    );
    return v ?? value;
  }

  void _showCourseDetail(CourseInfoJson courseInfo) {
    final course = courseInfo.main.course;
    Get.back();
    final studentId = LocalStorage.instance.getCourseSetting().info.studentId;
    if (course.id.isEmpty) {
      MyToast.show(course.name + R.current.noSupport);
    } else {
      RouteUtils.toISchoolPage(studentId, courseInfo).then((value) {
        if (value != null) {
          final semesterSetting = LocalStorage.instance.getCourseSetting().info.courseSemester;
          _getCourseTable(semesterSetting: semesterSetting, studentId: value);
        }
      });
    }
  }

  void _unFocusStudentInput() {
    FocusScope.of(context).requestFocus(FocusNode()); //失焦使鍵盤關閉
    _studentFocus.unfocus();
  }

  void _showCourseTable(CourseTableJson courseTable) async {
    if (courseTable == null) {
      return;
    }
    getCourseNotice(); //查詢訂閱的課程是否有公告
    courseTableData = courseTable;
    _studentIdControl.text = courseTable.studentId;
    _unFocusStudentInput();
    setState(() {
      isLoading = true;
    });
    courseTableControl.set(courseTable); //設定課表顯示狀態
    await Future.delayed(const Duration(milliseconds: 50));
    setState(() {
      isLoading = false;
    });
    favorite = (LocalStorage.instance.getCourseTable(courseTable.studentId, courseTable.courseSemester) != null);
    if (favorite) {
      LocalStorage.instance.addCourseTable(courseTableData);
    }
  }

  static const platform = MethodChannel(AppConfig.methodChannelName);

  Future screenshot() async {
    final originHeight = courseHeight;
    final renderObject = _key.currentContext.findRenderObject();
    final height = renderObject.semanticBounds.size.height - studentIdHeight - dayHeight;
    final RenderRepaintBoundary boundary = overRepaintKey.currentContext.findRenderObject();
    final directory = await getApplicationSupportDirectory();
    final path = directory.path;

    setState(() => courseHeight = height / courseTableControl.getSectionIntList.length);

    await Future.delayed(const Duration(milliseconds: 100));
    setState(() => isLoading = true);

    Log.d(path);

    final image = await boundary.toImage(pixelRatio: 2);

    setState(() {
      courseHeight = originHeight;
      isLoading = false;
    });

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData.buffer.asUint8List();
    final imgFile = File('$path/course_widget.png');

    await imgFile.writeAsBytes(pngBytes);

    final result = await platform.invokeMethod('update_home_screen_weight');

    Log.d("complete $result");

    if (result) {
      MyToast.show(R.current.settingComplete);
    } else {
      MyToast.show(R.current.settingCompleteWithError);
    }
  }
}
