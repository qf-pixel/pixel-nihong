# 数据库导出与初始化说明

本项目的数据库结构已经整理在：

```text
database/init.sql
```

接收方必须先在 MySQL 中执行该文件，再启动 JAR。

---

## 1. 从本机 MySQL 导出

### 方式 A：Navicat（图形界面）

1. 连接本地 MySQL。
2. 右键数据库 `kids_math`。
3. 选择“转储 SQL 文件” → “结构和数据”。
4. 保存为 `kids_math_full.sql`。
5. 如果只想导出结构：
   - 选择“仅结构”。
   - 保存为 `kids_math_schema.sql`。

### 方式 B：mysqldump（命令行）

只导出结构：

```bat
mysqldump -u root -p ^
  --databases kids_math ^
  --no-data ^
  --routines ^
  --triggers ^
  --default-character-set=utf8mb4 ^
  --set-gtid-purged=OFF ^
  > kids_math_schema.sql
```

导出结构 + 全部数据：

```bat
mysqldump -u root -p ^
  --databases kids_math ^
  --single-transaction ^
  --routines ^
  --triggers ^
  --default-character-set=utf8mb4 ^
  --set-gtid-purged=OFF ^
  > kids_math_full.sql
```

命令会提示输入 root 密码。

> 分享给其他人时，不建议直接给包含真实用户手机号和练习记录的完整数据文件。  
> 推荐只给结构，再加上 `database/init.sql` 里的演示账号。

---

## 2. 一个可分享的 SQL 文件应包含什么

按顺序建议包含：

1. 字符集设置：
   ```sql
   SET NAMES utf8mb4;
   ```
2. 建库：
   ```sql
   CREATE DATABASE IF NOT EXISTS kids_math
     DEFAULT CHARACTER SET utf8mb4
     DEFAULT COLLATE utf8mb4_unicode_ci;
   ```
3. 使用数据库：
   ```sql
   USE kids_math;
   ```
4. 所有建表语句，包括：
   - `users`
   - `binding_code`
   - `parent_student_binding`
   - `practice_session`
   - `practice_question`
   - `practice_answer`
   - `wrong_question`
   - `practice_task`
   - `notification`
   - `pk_challenge`
   - `pk_challenge_question`
   - `pk_challenge_answer`
   - `phase0_smoke_test`
5. 可选的演示数据：
   - 学生账号
   - 家长账号
   - 家长-学生绑定关系

当前项目的 `database/init.sql` 已经包含以上全部内容。

---

## 3. 接收方导入步骤

### Navicat

1. 连接自己的 MySQL。
2. “运行 SQL 文件” → 选择 `database/init.sql`。
3. 编码选择 UTF-8 / utf8mb4。
4. 执行完成。
5. 刷新后确认存在 `kids_math` 数据库和 13 张表。

### 命令行

```bat
mysql -u root -p --default-character-set=utf8mb4 < database\init.sql
```

---

## 4. 必须注意的顺序

```text
安装 MySQL 8
    ↓
导入 database/init.sql
    ↓
修改 application.properties
    ↓
启动 JAR
```

如果先启动 JAR，通常会看到：

```text
Unknown database 'kids_math'
```

或：

```text
Table 'kids_math.users' doesn't exist
```

这不是程序 Bug，而是数据库还没有准备好。
