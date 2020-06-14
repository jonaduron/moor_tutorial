import 'package:moor_flutter/moor_flutter.dart';

part 'moor_database.g.dart';

class Tasks extends Table {
  //IntColumn get id => integer().autoIncrement().call();
  // autoIncrement automatically sets this to be the primaryKey of the table
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tagName => text().nullable().customConstraint('NULL REFERENCES tags(name)')();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get completed => boolean().withDefault(Constant(false))();
}

class Tags extends Table {
  TextColumn get name => text().withLength(min: 1, max:10)();
  IntColumn get color => integer()();

  @override
  Set<Column> get primaryKey => {name};
}

class TaskWithTag {
  final Task task;
  final Tag tag;

  TaskWithTag({
    @required this.task,
    @required this.tag
  });
}

@UseMoor(tables: [Tasks, Tags], daos: [TaskDao, TagDao])
class AppDatabase extends _$AppDatabase {
  AppDatabase() 
    : super(FlutterQueryExecutor.inDatabaseFolder(
      path: 'db.sqlite', 
      logStatements: true )
    );

  // it has to de indicated where there're changes in the database model
  @override 
  int get schemaVersion => 2;  

  @override
  MigrationStrategy get migration => 
  MigrationStrategy(
    onUpgrade: (migrator, from, to) async {
      if(from == 1) {
        await migrator.addColumn(tasks, tasks.tagName);
        await migrator.createTable(tags);
      }
    },
    beforeOpen: (db, details) async {
      await db.customStatement('PRAGMA foreign_keys = ON');
    }, 
  );
}

@UseDao(
  tables: [Tasks, Tags], 
  queries: {
    // second version of the queries, the generator creates the query automatically
    'completedTasksGenerated' : 'SELECT * FROM tasks WHERE completed = 1 ORDER BY due_Date DESC, name;'
  },
)
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  final AppDatabase db;

  TaskDao(this.db) : super(db);

  Future<List<Task>> getAllTasks() => select(tasks).get();

  Stream<List<TaskWithTag>> watchAllTasks() { 
    return (select(tasks)
      ..orderBy(
        [ 
          (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.desc),
          (t) => OrderingTerm(expression: t.name),
        ]
      )).join(
        [
          leftOuterJoin(tags, tags.name.equalsExp(tasks.tagName)),
        ],
      ).watch()
      .map((rows) => rows.map((row) {
        return TaskWithTag(task: row.readTable(tasks), tag: row.readTable(tags));
      }).toList());
  }

  // first version of the queries, is all dart typed, so it says fluent syntaxe 
  Stream<List<Task>> watchCompletedTasks() { 
    return (select(tasks)
      ..orderBy([
        (t) => OrderingTerm(expression: t.dueDate, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.name),
      ])
      ..where((t) => t.completed.equals(true)))
      .watch();
  }
  
  // third version of the queries, is all custom by our own, we create ir completely, non typed safe 
  Stream<List<Task>> watchCompletedTasksCustom() {
    return customSelectStream(
        'SELECT * FROM tasks WHERE completed = 1 ORDER BY due_Date DESC, name;',
        readsFrom: {tasks}
      ).map((rows) {
        return rows.map((row) => Task.fromData(row.data, db)).toList();
      });
  }

  Future insertTask(Insertable<Task> task) => into(tasks).insert(task);
  Future updateTask(Insertable<Task> task) => update(tasks).replace(task);
  Future deleteTask(Insertable<Task> task) => delete(tasks).delete(task);
}

@UseDao(tables: [Tags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  AppDatabase db;

  TagDao(db) : super(db);
  
  Stream<List<Tag>> watchTags() => select(tags).watch();
  Future insertTag(Insertable<Tag> tag) => into(tags).insert(tag);
}
