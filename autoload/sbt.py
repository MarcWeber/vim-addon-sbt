import sys, tokenize, cStringIO, types, socket, string, os, re
from subprocess import Popen, PIPE, STDOUT

try:

  import vim

  is_vim = True
  DEBUG = vim.eval('g:sbt_debug') != '0'
  TEMP_NAME = vim.eval("tempname()")
  SBT_JAR = vim.eval('SBT_JAR()')


  # TODO use vimQuote everywhere
  def vimQuote(s):
    return '"%s"' % s.replace('"', '\\"').replace("\n", "\\n")

  def debug(s):
    vim.command("echoe '%s'" % vimQuote(s))

  def ask_user(question):
    return vim.eval("input('%s')" % question)

except ImportError, e:

  is_vim = False
  DEBUG = True
  TEMP_NAME = "/tmp/file"
  print "tempfile is ", TEMP_NAME
  SBT_JAR = os.environ.get("SBT_JAR")
  if SBT_JAR == None:
    print "You have to set env var SBT_JAR!"
    sys.exit(1)

  print "JAR IS %s" % SBT_JAR

  def debug(s):
    print "debug: ", s

  def ask_user(question):
    print "ABC"
    print question
    return raw_input()

if not globals().has_key('sbtCompiler'):

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
      except StartupException, e:
        out.write("==!> STARTUP / RELEOAD ERROR ! !")
        out.write(e.__str__()+"\n")
        out.flush()
        self.startUpError = self.tmpFile

    
    def waitFor(self, pattern, out):
      """ wait until pattern is found in an output line. Write non matching lines to out """


      error_in_project = " Hit enter to retry or 'exit' to quit:"
      # This will break.. :-/ (TODO)
      pats = [ "Project does not exist, create new project? (y/N/s) ",
              error_in_project,
              "Name: ",
              "Organization: ",
              "Version [1.0]: ",
              "Scala version [2.7.7]: ",
              "sbt version [0.7.4]: " ]

      allPatterns = pats[:]
      allPatterns.append(pattern)

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

        match = re.match(pattern, line)
        if match != None:
          return match
        elif out != None:
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
        c = self.sbt_o.read(1)
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
      line = read + self.sbt_o.readline()
      # remove trailing \n
      line=line[:-1]
      if self.debug:
        debug("full line: %s" % line)
      return line

    def waitForShell(self, out):
      self.waitFor("> ", out)
    
    def sbt(self, args):
      out = open(self.tmpFile, 'w')
      if args == ["\t"]:
        cmd = "\t"
      else:
        cmd = " ".join(args)+"\n"

      self.sbt_i.write(cmd)
      self.sbt_i.flush()
      # res = self.waitFor(".*Total time: .*completed.*", out)
      self.waitForShell(out)
      out.close()
      return self.tmpFile

  sbtCompiler = SBTCompiler()


if not is_vim:

  if sbtCompiler.startUpError != "":
    print "startup error: ", sbtCompiler.startUpError

  else:
    while True:
      print sbtCompiler.sbt(ask_user('sbt command:'))
