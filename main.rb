require 'pry'

require 'sqlite3'

$db = SQLite3::Database.new "test.db"
$db.results_as_hash = true

$db.execute "DROP TABLE IF EXISTS tuples;"

rows = $db.execute <<-SQL
  CREATE TABLE tuples (
    object text NOT NULL,
    object_namespace text NOT NULL,
    relation text NOT NULL,
    subject text NOT NULL,
    subject_namespace text, -- nullable because only valid if subject set
    subject_relation text -- again only applicable for subject sets
);
SQL

$db.execute <<-SQL
INSERT INTO tuples (object, object_namespace, relation, subject, subject_namespace, subject_relation) VALUES
    ('/cats', 'videos', 'owner', 'cat lady', NULL, NULL),
    ('/cats', 'videos', 'view', '/cats', 'videos', 'owner'),
    ('/cats/2.mp4', 'videos', 'owner', '/cats', 'videos', 'owner'),
    ('/cats/2.mp4', 'videos', 'view', '/cats', 'videos', 'owner'),
    ('/cats/1.mp4', 'videos', 'view', '*', NULL, NULL),
    ('/cats/1.mp4', 'videos', 'owner', '/cats', 'videos', 'owner'),
    ('/cats/1.mp4', 'videos', 'view', '/cats/1.mp4', 'videos', 'owner'),
    ('1', 'claims', 'view', '111', 'users', null),
    ('1', 'policy', 'view', '1', 'org', 'member'),
    ('1', 'org', 'member', '111', 'users', null),

    ('*', 'car', 'view', '2', 'org', 'member'),
    ('2', 'org', 'member', '222', 'users', null),
    ('3', 'org', 'member', '222', 'users', null),
    ('1', 'enrollment', 'reader', '222', 'users', null),

    ('4', 'org', 'member', '331', 'users', null),
    ('4', 'org', 'owner', '333', 'users', null),
    ('1', 'dir', 'owner', '4', 'org', 'owner'),
    ('1', 'file', 'owner', '1', 'dir', 'owner')
    ;
SQL

$check_sql = <<-SQL
  SELECT
      object,
      object_namespace,
      relation,
      subject,
      subject_namespace,
      subject_relation
    FROM
      tuples
    WHERE
      object_namespace = ?
      AND (object = ? OR object = '*')
      AND relation = ?
    ORDER BY
      subject_relation NULLS FIRST
SQL

def check?(p_subject_namespace, p_subject, p_relation, p_object_namespace, p_object)
  $db.execute( $check_sql, [p_object_namespace, p_object, p_relation]) do |var_r|
    if var_r['subject'] == p_subject && var_r['subject_namespace'] == p_subject_namespace
      return true
    end

    if var_r['subject_namespace'] != nil && var_r['subject_relation'] != nil

      # p [p_subject_namespace, p_subject, var_r['subject_relation'], var_r['subject_namespace'], var_r['subject']]
      var_b = check?(p_subject_namespace, p_subject, var_r['subject_relation'], var_r['subject_namespace'], var_r['subject'])
      if var_b
        return true
      end
    end
  end

  return false
end

$enumerate_sql = <<-SQL
  SELECT
    object,
    object_namespace,
    relation,
    subject,
    subject_namespace,
    subject_relation
  FROM
    tuples
  WHERE
    subject = ?
    AND subject_namespace = ?
    AND (subject_relation = ? OR subject_relation IS ?)
  ORDER BY
    subject_relation NULLS FIRST
SQL

def enumerate(p_subject_namespace, p_subject, p_subject_relation=nil, relations = [])
  $db.execute( $enumerate_sql, [p_subject, p_subject_namespace, p_subject_relation, p_subject_relation]) do |var_r|
    relations.push "#{var_r['relation']}@#{var_r['object_namespace']}:#{var_r['object']}"
    relations = enumerate(var_r['object_namespace'], var_r['object'], var_r['relation'], relations)
  end

  return relations
end

###
# simulating what relations you'll have if you add another tuple in
###

$simulate_enumerate_sql = <<-SQL
with simulated_tuples as (
  select * from tuples
  union
  select ?, ?, ?, ?, ?, ?
)
  SELECT
    object,
    object_namespace,
    relation,
    subject,
    subject_namespace,
    subject_relation
  FROM
    simulated_tuples
  WHERE
    subject = ?
    AND subject_namespace = ?
    AND (subject_relation = ? OR subject_relation IS ?)
  ORDER BY
    subject_relation NULLS FIRST
SQL

def simulate_enumerate(p_subject_namespace, p_subject, sim_relation, sim_object_namespace, sim_object, p_subject_relation=nil, relations = [])
  simulated_tuple = [sim_object, sim_object_namespace, sim_relation, p_subject, p_subject_namespace, nil]
  binds = [ *simulated_tuple, p_subject, p_subject_namespace, p_subject_relation, p_subject_relation]

  $db.execute( $simulate_enumerate_sql, binds) do |var_r|
    relations.push "#{var_r['relation']}@#{var_r['object_namespace']}:#{var_r['object']}"
    relations = enumerate(var_r['object_namespace'], var_r['object'], var_r['relation'], relations)
  end

  return relations
end

def assert?(val) = unless val; fail; else; true; end
def assert_eq?(val, other) = unless val.sort == other.sort; fail("#{val.sort} != #{other.sort}"); end

assert? check?("users", "111", "view", "claims", "1")
assert? check?("users", "111", "view", "policy", "1")
assert? ! check?("users", "1", "view", "policy", "1")
assert? check?("users", "222", "view", "car", "1")

def from_partial_tuple(partial_tuple)
  partial_tuple.match(/(\w+)@(\w+):(\d+)/).to_a[1..3]
end

assert_eq? enumerate('users', '222'), ['member@org:3', 'member@org:2', 'view@car:*', 'reader@enrollment:1']
assert? enumerate('users', '222').all? do |t|
  relation, object_namespace, object = from_partial_tuple(t)
  check?('users', '222', relation, object_namespace, object)
end

assert_eq? enumerate('users', '331'), ['member@org:4']
assert? enumerate('users', '331').all? do |t|
  relation, object_namespace, object = from_partial_tuple(t)
  check?('users', '331', relation, object_namespace, object)
end
assert_eq? enumerate('users', '333'), ['owner@org:4', 'owner@dir:1', 'owner@file:1']
assert? enumerate('users', '333').all? do |t|
  relation, object_namespace, object = from_partial_tuple(t)
  check?('users', '333', relation, object_namespace, object)
end



assert_eq? simulate_enumerate('users', '331', 'owner', 'org', '4'), ['member@org:4', 'owner@org:4', 'owner@dir:1', 'owner@file:1']

$db.query('select distinct subject from tuples where subject_namespace = ?', 'users').each do |tuples|
  p tuples['subject'] => enumerate('users', tuples['subject'])
end