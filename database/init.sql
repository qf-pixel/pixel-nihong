-- 霓虹像素夜校：完整数据库初始化脚本（MySQL 8）。
-- 逻辑：先建库，再按依赖顺序建用户、绑定、练习、错题、任务、通知和 PK 表。
-- 功能：提供可分享的表结构与演示账号，导入后即可启动 JAR。
-- 边界：不插入真实用户数据，不包含存储过程或触发器，不使用 JPA 对象。
-- 安全：只保留登录名、BCrypt 哈希、角色、昵称、可选年级、绑定和练习数据。

SET NAMES utf8mb4;

CREATE DATABASE IF NOT EXISTS kids_math
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE kids_math;

-- ============================================================
-- 1. 用户表：学生与家长共用；手机号仅作登录标识，角色注册后固定
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '用户主键',
    phone           CHAR(11)        NOT NULL                COMMENT '11 位手机号，唯一登录标识',
    password_hash   VARCHAR(100)    NOT NULL                COMMENT 'BCrypt 哈希，禁止存明文',
    role            VARCHAR(16)     NOT NULL                COMMENT 'STUDENT 或 PARENT，注册后固定',
    nickname        VARCHAR(30)     NOT NULL                COMMENT '页面显示昵称',
    grade           TINYINT UNSIGNED NULL                   COMMENT '学生年级 1-6；家长为 NULL',
    created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                             ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_users_phone (phone),
    KEY idx_users_role (role),
    CONSTRAINT chk_users_role
        CHECK (role IN ('STUDENT', 'PARENT')),
    CONSTRAINT chk_users_grade
        CHECK (grade IS NULL OR grade BETWEEN 1 AND 6)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '学生/家长账号；手机号仅用于登录';

-- ============================================================
-- 2. 一次性绑定码：由学生生成，6 位数字，30 分钟有效，只能成功使用一次
-- ============================================================
CREATE TABLE IF NOT EXISTS binding_code (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '绑定码主键',
    student_id          BIGINT UNSIGNED NOT NULL                COMMENT '生成绑定码的学生',
    code                CHAR(6)         NOT NULL                COMMENT '6 位数字码；全局唯一',
    expires_at          DATETIME(3)     NOT NULL                COMMENT '过期时间，生成后 30 分钟',
    used_at             DATETIME(3)     NULL                    COMMENT '实际使用时间；NULL 表示未使用',
    used_by_parent_id   BIGINT UNSIGNED NULL                    COMMENT '使用该码的家长',
    created_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_binding_code_code (code),
    KEY idx_binding_code_student_expiry (student_id, used_at, expires_at),
    KEY idx_binding_code_parent (used_by_parent_id),
    CONSTRAINT fk_binding_code_student
        FOREIGN KEY (student_id) REFERENCES users (id),
    CONSTRAINT fk_binding_code_parent
        FOREIGN KEY (used_by_parent_id) REFERENCES users (id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '学生生成的一次性家长绑定码';

-- ============================================================
-- 3. 家长-学生绑定：多对多；unbound_at IS NULL 表示当前有效绑定
-- 解绑后家长查询必须在服务端带上 unbound_at IS NULL 条件
-- ============================================================
CREATE TABLE IF NOT EXISTS parent_student_binding (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '绑定关系主键',
    parent_id   BIGINT UNSIGNED NOT NULL                COMMENT '家长用户',
    student_id  BIGINT UNSIGNED NOT NULL                COMMENT '学生用户',
    bound_at    DATETIME(3)     NOT NULL                COMMENT '本次绑定生效时间',
    unbound_at  DATETIME(3)     NULL                    COMMENT '解绑时间；NULL 表示当前有效',
    created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                         ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_parent_student (parent_id, student_id),
    KEY idx_binding_student_active (student_id, unbound_at),
    KEY idx_binding_parent_active (parent_id, unbound_at),
    CONSTRAINT fk_binding_parent
        FOREIGN KEY (parent_id) REFERENCES users (id),
    CONSTRAINT fk_binding_student
        FOREIGN KEY (student_id) REFERENCES users (id),
    CONSTRAINT chk_binding_not_self
        CHECK (parent_id <> student_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '家长与学生多对多绑定；解绑保留行但清空访问权';

-- ============================================================
-- 4. 阶段5预留：家长布置的练习任务；阶段0只建表，不写业务代码
-- ============================================================
CREATE TABLE IF NOT EXISTS practice_task (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '任务主键',
    parent_id       BIGINT UNSIGNED NOT NULL                COMMENT '布置任务的家长',
    student_id      BIGINT UNSIGNED NOT NULL                COMMENT '被布置任务的学生',
    practice_mode   VARCHAR(16)     NOT NULL                COMMENT 'ADD/SUB/MUL/DIV/MIXED',
    difficulty      VARCHAR(8)      NOT NULL                COMMENT 'L1/L2/L3',
    question_count  SMALLINT UNSIGNED NOT NULL              COMMENT '5~1000 题',
    max_number      INT UNSIGNED    NOT NULL DEFAULT 100    COMMENT '操作数和结果上限',
    status          VARCHAR(16)     NOT NULL DEFAULT 'ASSIGNED'
                                                   COMMENT 'ASSIGNED/COMPLETED/CANCELLED',
    due_at          DATETIME(3)     NULL                    COMMENT '可选截止时间',
    created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                             ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    KEY idx_task_student_status (student_id, status, created_at),
    KEY idx_task_parent (parent_id),
    CONSTRAINT fk_task_parent
        FOREIGN KEY (parent_id) REFERENCES users (id),
    CONSTRAINT fk_task_student
        FOREIGN KEY (student_id) REFERENCES users (id),
    CONSTRAINT chk_task_mode
        CHECK (practice_mode IN ('ADD', 'SUB', 'MUL', 'DIV', 'MIXED')),
    CONSTRAINT chk_task_difficulty
        CHECK (difficulty IN ('L1', 'L2', 'L3')),
    CONSTRAINT chk_task_count
        CHECK (question_count BETWEEN 5 AND 1000),
    CONSTRAINT chk_task_status
        CHECK (status IN ('ASSIGNED', 'COMPLETED', 'CANCELLED'))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '阶段5预留：家长布置的练习任务';

-- ============================================================
-- 5. 练习会话：开始后保存不可变配置；同一学生最多一个 IN_PROGRESS
-- active_student_id 是生成列，只在进行中等于 student_id，配合唯一索引防并发
-- ============================================================
CREATE TABLE IF NOT EXISTS practice_session (
    id                 BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '练习会话主键',
    student_id         BIGINT UNSIGNED NOT NULL                COMMENT '作答学生',
    task_id            BIGINT UNSIGNED NULL                    COMMENT '阶段5任务来源；自主练习为 NULL',
    source_type        VARCHAR(20)     NOT NULL DEFAULT 'SELF'
                                                   COMMENT 'SELF/TASK/WRONG_RETRY',
    play_mode          VARCHAR(20)     NOT NULL DEFAULT 'NORMAL'
                                                   COMMENT 'NORMAL/TIME_ATTACK',
    time_limit_seconds INT UNSIGNED    NULL                    COMMENT '限时挑战秒数；普通练习为 NULL',
    practice_mode      VARCHAR(16)     NOT NULL                COMMENT 'ADD/SUB/MUL/DIV/MIXED',
    difficulty         VARCHAR(8)      NOT NULL                COMMENT 'L1/L2/L3',
    question_count     SMALLINT UNSIGNED NOT NULL              COMMENT '普通练习 5~1000；错题重练为 1',
    max_number         INT UNSIGNED    NOT NULL DEFAULT 100    COMMENT '开始后不可改：操作数和结果上限',
    status             VARCHAR(16)     NOT NULL DEFAULT 'IN_PROGRESS'
                                                   COMMENT 'IN_PROGRESS/COMPLETED/EXPIRED',
    started_at         DATETIME(3)     NOT NULL                COMMENT '服务端开始时间',
    expires_at         DATETIME(3)     NOT NULL                COMMENT '服务端开始后 7 天',
    completed_at       DATETIME(3)     NULL                    COMMENT '完成时间',
    elapsed_seconds    INT UNSIGNED    NULL                    COMMENT '开始到完成的总秒数，含中断',
    correct_count      SMALLINT UNSIGNED NULL                  COMMENT '答对题数，完成时写入',
    game_score         SMALLINT UNSIGNED NULL                  COMMENT '限时挑战得分；普通练习为 NULL',
    completion_reason  VARCHAR(20)     NULL                    COMMENT 'ALL_ANSWERED/TIME_UP/FAILED/ABANDONED',
    active_student_id  BIGINT UNSIGNED GENERATED ALWAYS AS (
                           CASE WHEN status = 'IN_PROGRESS' THEN student_id ELSE NULL END
                       ) STORED COMMENT '仅进行中会话有值，用于唯一约束',
    created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
                                             ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_practice_session_active_student (active_student_id),
    KEY idx_session_student_status_started (student_id, status, started_at),
    UNIQUE KEY uk_session_task (task_id),
    KEY idx_session_expiry (status, expires_at),
    KEY idx_session_leaderboard (status, source_type, student_id, correct_count, question_count),
    KEY idx_session_student_play_mode_started (student_id, play_mode, started_at),
    CONSTRAINT fk_session_student
        FOREIGN KEY (student_id) REFERENCES users (id),
    CONSTRAINT fk_session_task
        FOREIGN KEY (task_id) REFERENCES practice_task (id)
        ON DELETE SET NULL,
    CONSTRAINT chk_session_source
        CHECK (source_type IN ('SELF', 'TASK', 'WRONG_RETRY')),
    CONSTRAINT chk_session_play_mode
        CHECK (play_mode IN ('NORMAL', 'TIME_ATTACK')),
    CONSTRAINT chk_session_time_limit
        CHECK (time_limit_seconds IS NULL OR time_limit_seconds BETWEEN 30 AND 3600),
    CONSTRAINT chk_session_game_score
        CHECK (game_score IS NULL OR game_score BETWEEN 0 AND 1000),
    CONSTRAINT chk_session_completion_reason
        CHECK (
            completion_reason IS NULL
            OR completion_reason IN ('ALL_ANSWERED', 'TIME_UP', 'FAILED', 'ABANDONED')
        ),
    CONSTRAINT chk_session_time_attack
        CHECK (
            play_mode <> 'TIME_ATTACK'
            OR (question_count = 20 AND time_limit_seconds = 180)
        ),
    CONSTRAINT chk_session_mode
        CHECK (practice_mode IN ('ADD', 'SUB', 'MUL', 'DIV', 'MIXED')),
    CONSTRAINT chk_session_difficulty
        CHECK (difficulty IN ('L1', 'L2', 'L3')),
    CONSTRAINT chk_session_count
        CHECK (
            (source_type = 'WRONG_RETRY' AND question_count BETWEEN 1 AND 20)
            OR (source_type <> 'WRONG_RETRY' AND question_count BETWEEN 5 AND 1000)
        ),
    CONSTRAINT chk_session_status
        CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'EXPIRED')),
    CONSTRAINT chk_session_count_correct
        CHECK (correct_count IS NULL OR correct_count <= question_count),
    CONSTRAINT chk_session_expiry
        CHECK (expires_at > started_at)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '练习会话与固定配置快照';

-- ============================================================
-- 6. 固定题目快照：开始练习时一次性写入，之后只读，保证刷新可恢复
-- ============================================================
CREATE TABLE IF NOT EXISTS practice_question (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '题目主键',
    session_id      BIGINT UNSIGNED NOT NULL                COMMENT '所属练习会话',
    seq_no          SMALLINT UNSIGNED NOT NULL              COMMENT '题号，从 1 开始',
    question_text   VARCHAR(50)     NOT NULL                COMMENT '展示快照，如 12 + 34 = ?',
    left_operand    INT UNSIGNED    NOT NULL                COMMENT '左操作数',
    right_operand   INT UNSIGNED    NOT NULL                COMMENT '右操作数',
    operator        CHAR(1)         NOT NULL                COMMENT '+ - * /',
    correct_answer  INT UNSIGNED    NOT NULL                COMMENT '服务端计算的正确答案',
    created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_question_session_seq (session_id, seq_no),
    CONSTRAINT fk_question_session
        FOREIGN KEY (session_id) REFERENCES practice_session (id),
    CONSTRAINT chk_question_operator
        CHECK (operator IN ('+', '-', '*', '/'))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '练习题目不可变快照';

-- ============================================================
-- 7. 逐题答案：每道题最多一条，服务端判分；唯一键用于幂等防重复提交
-- ============================================================
CREATE TABLE IF NOT EXISTS practice_answer (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '答案主键',
    session_id       BIGINT UNSIGNED NOT NULL                COMMENT '所属练习会话',
    question_id      BIGINT UNSIGNED NOT NULL                COMMENT '对应题目',
    submitted_answer INT             NOT NULL                COMMENT '学生提交的答案，可为负以记录错误',
    is_correct       TINYINT(1)      NOT NULL                COMMENT '服务端判定：1 对，0 错',
    answered_at      DATETIME(3)     NOT NULL                COMMENT '服务端接收答案时间',
    created_at       DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_answer_question (question_id),
    KEY idx_answer_session (session_id),
    CONSTRAINT fk_answer_session
        FOREIGN KEY (session_id) REFERENCES practice_session (id),
    CONSTRAINT fk_answer_question
        FOREIGN KEY (question_id) REFERENCES practice_question (id),
    CONSTRAINT chk_answer_correct
        CHECK (is_correct IN (0, 1))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '逐题作答记录与判分结果';

-- ============================================================
-- 8. 错题本：保存题目快照和错误答案；重练不改原始结果
-- ============================================================
CREATE TABLE IF NOT EXISTS wrong_question (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '错题主键',
    student_id      BIGINT UNSIGNED NOT NULL                COMMENT '归属学生',
    session_id      BIGINT UNSIGNED NOT NULL                COMMENT '首次答错的会话',
    question_id     BIGINT UNSIGNED NOT NULL                COMMENT '首次答错的题目',
    question_text   VARCHAR(50)     NOT NULL                COMMENT '题目文字快照',
    left_operand    INT UNSIGNED    NOT NULL                COMMENT '左操作数快照',
    right_operand   INT UNSIGNED    NOT NULL                COMMENT '右操作数快照',
    operator        CHAR(1)         NOT NULL                COMMENT '运算符快照',
    correct_answer  INT UNSIGNED    NOT NULL                COMMENT '正确答案快照',
    wrong_answer    INT             NOT NULL                COMMENT '学生错误答案快照',
    mastered_at     DATETIME(3)     NULL                    COMMENT '手动标记已掌握时间',
    created_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uk_wrong_question_source (question_id),
    KEY idx_wrong_student_mastered (student_id, mastered_at, created_at),
    KEY idx_wrong_session (session_id),
    CONSTRAINT fk_wrong_student
        FOREIGN KEY (student_id) REFERENCES users (id),
    CONSTRAINT fk_wrong_session
        FOREIGN KEY (session_id) REFERENCES practice_session (id),
    CONSTRAINT fk_wrong_question
        FOREIGN KEY (question_id) REFERENCES practice_question (id),
    CONSTRAINT chk_wrong_operator
        CHECK (operator IN ('+', '-', '*', '/'))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '错题快照、重练与已掌握标记';

-- ============================================================
-- 9. 阶段5预留：站内通知；不存手机号、邮箱等联系方式
-- ============================================================
CREATE TABLE IF NOT EXISTS notification (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '通知主键',
    user_id     BIGINT UNSIGNED NOT NULL                COMMENT '接收用户',
    type        VARCHAR(30)     NOT NULL                COMMENT 'TASK/REMINDER/NOTICE 等',
    title       VARCHAR(80)     NOT NULL                COMMENT '短标题',
    content     VARCHAR(500)    NOT NULL                COMMENT '站内正文',
    read_at     DATETIME(3)     NULL                    COMMENT '已读时间；NULL 表未读',
    created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    KEY idx_notification_user_read (user_id, read_at, created_at),
    CONSTRAINT fk_notification_user
        FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '阶段5预留：站内通知，不收集联系方式';

-- ============================================================
-- 10. 阶段6：异步 PK 挑战主表
-- ============================================================
CREATE TABLE IF NOT EXISTS pk_challenge (
    id                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '挑战主键',
    code                CHAR(6)         NOT NULL                COMMENT '6 位挑战码，全局唯一',
    challenger_id       BIGINT UNSIGNED NOT NULL                COMMENT '发起学生',
    opponent_id         BIGINT UNSIGNED NULL                    COMMENT '接受挑战的学生',
    practice_mode       VARCHAR(16)     NOT NULL                COMMENT 'ADD/SUB/MUL/DIV/MIXED',
    difficulty          VARCHAR(8)      NOT NULL                COMMENT 'L1/L2/L3',
    question_count      SMALLINT UNSIGNED NOT NULL              COMMENT '5~1000 题',
    max_number          INT UNSIGNED    NOT NULL DEFAULT 100    COMMENT '操作数和结果上限',
    status              VARCHAR(16)     NOT NULL DEFAULT 'WAITING'
                                                   COMMENT 'WAITING/IN_PROGRESS/COMPLETED/EXPIRED',
    challenger_correct  TINYINT UNSIGNED NULL                   COMMENT '发起人答对数',
    opponent_correct    TINYINT UNSIGNED NULL                   COMMENT '接受人答对数',
    created_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    accepted_at         DATETIME(3)     NULL                    COMMENT '接受挑战时间',
    completed_at        DATETIME(3)     NULL                    COMMENT '双方完成时间',
    expires_at          DATETIME(3)     NOT NULL                COMMENT '挑战码过期时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_pk_challenge_code (code),
    KEY idx_pk_status_expiry (status, expires_at),
    KEY idx_pk_challenger (challenger_id, created_at),
    KEY idx_pk_opponent (opponent_id, created_at),
    CONSTRAINT fk_pk_challenger
        FOREIGN KEY (challenger_id) REFERENCES users (id),
    CONSTRAINT fk_pk_opponent
        FOREIGN KEY (opponent_id) REFERENCES users (id),
    CONSTRAINT chk_pk_mode
        CHECK (practice_mode IN ('ADD', 'SUB', 'MUL', 'DIV', 'MIXED')),
    CONSTRAINT chk_pk_difficulty
        CHECK (difficulty IN ('L1', 'L2', 'L3')),
    CONSTRAINT chk_pk_count
        CHECK (question_count BETWEEN 5 AND 1000),
    CONSTRAINT chk_pk_status
        CHECK (status IN ('WAITING', 'IN_PROGRESS', 'COMPLETED', 'EXPIRED')),
    CONSTRAINT chk_pk_not_self
        CHECK (opponent_id IS NULL OR opponent_id <> challenger_id),
    CONSTRAINT chk_pk_scores
        CHECK (
            (challenger_correct IS NULL OR challenger_correct <= question_count)
            AND (opponent_correct IS NULL OR opponent_correct <= question_count)
        )
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '阶段6：异步 PK 挑战';

-- ============================================================
-- 11. 阶段6：PK 固定题目快照
-- ============================================================
CREATE TABLE IF NOT EXISTS pk_challenge_question (
    id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'PK 题目主键',
    challenge_id    BIGINT UNSIGNED NOT NULL                COMMENT '所属挑战',
    seq_no          SMALLINT UNSIGNED NOT NULL              COMMENT '题号',
    question_text   VARCHAR(50)     NOT NULL                COMMENT '题面快照',
    left_operand    INT UNSIGNED    NOT NULL                COMMENT '左操作数',
    right_operand   INT UNSIGNED    NOT NULL                COMMENT '右操作数',
    operator        CHAR(1)         NOT NULL                COMMENT '+ - * /',
    correct_answer  INT UNSIGNED    NOT NULL                COMMENT '正确答案',
    PRIMARY KEY (id),
    UNIQUE KEY uk_pk_question_seq (challenge_id, seq_no),
    CONSTRAINT fk_pk_question_challenge
        FOREIGN KEY (challenge_id) REFERENCES pk_challenge (id)
        ON DELETE CASCADE,
    CONSTRAINT chk_pk_question_operator
        CHECK (operator IN ('+', '-', '*', '/'))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '阶段6：PK 双方共用的固定题目快照';

-- ============================================================
-- 12. 阶段6：PK 双方逐题答案
-- ============================================================
CREATE TABLE IF NOT EXISTS pk_challenge_answer (
    id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT 'PK 答案主键',
    challenge_id     BIGINT UNSIGNED NOT NULL                COMMENT '所属挑战',
    student_id       BIGINT UNSIGNED NOT NULL                COMMENT '作答学生',
    question_id      BIGINT UNSIGNED NOT NULL                COMMENT 'PK 题目',
    submitted_answer INT             NOT NULL                COMMENT '提交答案',
    is_correct       TINYINT(1)      NOT NULL                COMMENT '服务端判分',
    answered_at      DATETIME(3)     NOT NULL                COMMENT '答题时间',
    PRIMARY KEY (id),
    UNIQUE KEY uk_pk_answer_once (challenge_id, student_id, question_id),
    KEY idx_pk_answer_student (challenge_id, student_id),
    CONSTRAINT fk_pk_answer_challenge
        FOREIGN KEY (challenge_id) REFERENCES pk_challenge (id)
        ON DELETE CASCADE,
    CONSTRAINT fk_pk_answer_student
        FOREIGN KEY (student_id) REFERENCES users (id),
    CONSTRAINT fk_pk_answer_question
        FOREIGN KEY (question_id) REFERENCES pk_challenge_question (id)
        ON DELETE CASCADE,
    CONSTRAINT chk_pk_answer_correct
        CHECK (is_correct IN (0, 1))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '阶段6：PK 双方逐题答案与判分';

-- ============================================================
-- 13. 阶段0专用：启动自检写入/读取/删除；阶段1可安全删除
-- ============================================================
CREATE TABLE IF NOT EXISTS phase0_smoke_test (
    id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自检记录主键',
    message     VARCHAR(100)    NOT NULL                COMMENT '自检文本',
    created_at  DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = '阶段0数据库读写自检表，可在阶段1删除';

-- ============================================================
-- 14. 可选测试账号：首次导入后可直接体验
-- 学生：13900000901 / demo1234
-- 家长：13900000902 / demo1234
-- 说明：密码为 BCrypt 哈希；手机号只用于本地演示，可自行修改。
-- ============================================================
INSERT INTO users (phone, password_hash, role, nickname, grade)
SELECT '13900000901',
       '$2a$10$VXCWW1o64s65vUtl.WbQluPufoFwI2xbTbWLBZIKTdNBoMuywXaeW',
       'STUDENT',
       'DemoStudent',
       3
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE phone = '13900000901'
);

INSERT INTO users (phone, password_hash, role, nickname, grade)
SELECT '13900000902',
       '$2a$10$DzPDsANZ/o/a90sdBTeq6.EV35pvVONmJEuI7g.Rw/efOBHw0OuzS',
       'PARENT',
       'DemoParent',
       NULL
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE phone = '13900000902'
);

INSERT INTO parent_student_binding (parent_id, student_id, bound_at)
SELECT p.id, s.id, CURRENT_TIMESTAMP(3)
FROM users p
JOIN users s ON s.phone = '13900000901'
WHERE p.phone = '13900000902'
  AND NOT EXISTS (
      SELECT 1
      FROM parent_student_binding b
      WHERE b.parent_id = p.id
        AND b.student_id = s.id
  );
