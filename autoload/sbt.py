import sys, tokenize, types, socket, string, os, re
from subprocess import Popen, PIPE, STDOUT

try:

  import vim

  is_vim = True
  DEBUG = vim.eval('g:sbt_debug') != '0'
  TEMP_NAME = vim.eval("tempname()")
  SBT_JAR = vim.eval('SBT_JAR()')


  # TODO use vimQuote everywhere
  def vimQuote(s):
    return '"%s"' % s.replace("\\","\\\\").replace('"', '\\"').replace("\n", "\\n")

  def debug(s):
    vim.command("echoe '%s'" % vimQuote(s))

  def ask_user(question):
    return vim.eval("input('%s')" % question)

except ImportError as e:

  is_vim = False
  DEBUG = True
  TEMP_NAME = "/tmp/file"
  print ("tempfile is " ,TEMP_NAME)
  SBT_JAR = os.environ.get("SBT_JAR")
  if SBT_JAR == None:
    print ("You have to set env var SBT_JAR!")
    sys.exit(1)

  print ("JAR IS %s" % SBT_JAR)

  def debug(s):
    print ("debug: ", s)

  def ask_user(question):
    print ("ABC")
    print (question)
    return raw_input()

if not 'sbtCompiler' in globals():

  class StartupException(Exception):

       def __init__(self, value):
           self.parameter = value

       def __str__(self):
           return repr(self.parameter)

  # sbt_dict keeps compilation ids
  sbt_dict = {}

  class SBTCompiler():

    # sets startUpError to file on error
    def __init__(self):
      self.debug = DEBUG
      self.tmpFile = TEMP_NAME
      self.ids = {}
      # errors are print to stderr. We want to catch them!
      # start interactive mode so that we can recompile without reloading sbt

      p = Popen(["java","-Dsbt.log.noformat=true","-jar", SBT_JAR], \
            shell = False, bufsize = 1, stdin = PIPE, stdout = PIPE, stderr = STDOUT)

      self.sbt_o = p.stdout
      self.sbt_i = p.stdin

      try:
        out = open(self.tmpFile, 'w')
        self.waitForShell(out)
        self.startUpError = ""
      except StartupException as e:
        out.write("==!> STARTUP / RELEOAD ERROR ! !")
        out.write(e.__str__()+"\n")
        out.flush()
        self.startUpError = self.tmpFile

    
    def waitFor(self, patterns, out):
      """ wait until one of patterns is found in an output line. Write non matching lines to out """


      error_in_project = " Hit enter to retry or 'exit' to quit:"
      error_during_sbt_execution = "Error during sbt execution: "
      # This will break.. :-/ (TODO)
      pats = [ "Project does not exist, create new project? (y/N/s) ",
              "Provide a new Scala version or press enter to exit: ",
              "Project loading failed: (r)etry, (q)uit, (l)ast, or (i)gnore?",
              error_in_project,
              "Name: ",
              "Organization: ",
              "Version [1.0]: ",
              "Scala version [2.7.7]: ",
              "sbt version [0.7.4]: "
            ]

      allPatterns = pats[:]
      allPatterns.extend(patterns)

      while 1:
        if self.debug:
          debug("waiting for one of the patterns")
        line = self.readLineSkip(allPatterns)

        if line == error_in_project:
          raise StartupException("sbt asked to retry or exit. Fix the problem, then run :SBT to retry or restart Vim")

        # hack: forward pat question to user
        if line in pats:
          self.sbt_i.write(ask_user(line)+"\n")
          self.sbt_i.flush()
          continue

        for p in patterns:
          match = re.match(p, line)
          if match != None:
            return match
        if out != None:
          out.write(line+"\n")


    # the input line usually don't end with \n
    # so break on those queries
    # probably this can be implemented more efficiently
    def readLineSkip(self, patterns):
      # copy list:
      l = patterns[:]
      idx = 0
      read = ""

      while len(l) > 0:

        if self.debug:
          debug('waiting for char. Received bytes: %s' % read)
        # TODO: think about encoding!
        c = self.sbt_o.read(1).decode('utf-8')
        if self.debug:
          debug("got char: X%sX" % c)
        if c == "\n":
          return read
        else:
          read = read+c

        # remove patterns from list which can no longer match
        for i in range(len(l)-1,-1,-1):
          if l[i][idx] != c:
            # this pattern can no longer match
            r = l.pop(i)
            if self.debug:
              debug("popping %s" % r)
          else:
            # full match
            if len(l[i]) == idx+1:
              return read
        idx += 1

      if self.debug:
        debug("waiting for eol. Received bytes: %s" % read)
      # TODO: think about encoding
      line = read + self.sbt_o.readline().decode('utf-8')
      # remove trailing \n
      line=line[:-1]
      if self.debug:
        debug("full line: %s" % line)
      return line

    def waitForShell(self, out):
      self.waitFor(["> ","Error during sbt execution: "], out)
    
    def sbt(self, args):
      out = open(self.tmpFile, 'w')
      if args == ["\t"]:
        cmd = "\t"
      else:
        cmd = " ".join(args)+"\n"

      self.sbt_i.write(cmd)
      self.sbt_i.flush()
      # res = self.waitFor([".*Total time: .*completed.*"], out)
      self.waitForShell(out)
      out.close()
      return self.tmpFile

  sbtCompiler = SBTCompiler()


if not is_vim:

  if sbtCompiler.startUpError != "":
    print ("startup error: ", sbtCompiler.startUpError)

  else:
    while True:
      print (sbtCompiler.sbt(ask_user('sbt command:')))
