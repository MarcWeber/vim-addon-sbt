import sys, tokenize, cStringIO, types, socket, string, os, re
from subprocess import Popen, PIPE

try:

  import vim

  is_vim = True
  DEBUG = vim.eval('g:sbt_debug')
  TEMP_NAME = vim.eval("tempname()")
  SBT_JAR = vim.eval('SBT_JAR()')

  def debug(s):
    # should be escaped..
    vim.command("echoe '%s'" % s)

  def ask_user(question):
    return vim.eval("input('%s')" % s)

except ImportError, e:

  is_vim = False
  DEBUG = True
  TEMP_NAME = "/tmp/file"
  SBT_JAR = os.environ.get("SBT_JAR")
  print "JAR IS %s" % SBT_JAR

  def debug(s):
    print "debug: ", s

  def ask_user(question):
    print "ABC"
    print question
    return raw_input()

if not globals().has_key('sbtCompiler'):

  # sbt_dict keeps compilation ids
  sbt_dict = {}

  class SBTCompiler():

    def __init__(self):
      self.debug = DEBUG
      self.tmpFile = TEMP_NAME
      self.ids = {}
      # errors are print to stderr. We want to catch them!
      # start interactive mode so that we can recompile without reloading sbt

      p = Popen(["java","-Dsbt.log.noformat=true","-jar", SBT_JAR], \
            shell = False, bufsize = 1, stdin = PIPE, stdout = PIPE, stderr = PIPE)

      self.sbt_o = p.stdout
      self.sbt_i = p.stdin

      self.waitForShell(None)
    
    def waitFor(self, pattern, out):
      """ wait until pattern is found in an output line. Write non matching lines to out """

      # This will break.. :-/ (TODO)
      pats = [ "Project does not exist, create new project? (y/N/s) ",
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
          debug("got char: %s" % c)
        if c == "\n":
          return read
        else:
          read = read+c

        # remove patterns from list which can no longer match
        for i in range(len(l)-1,-1,-1):
          if l[i][idx] != c:
            # this pattern can no longer match
            l.pop(i)
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
        debug("full line: %s" % read)
      return line

    def waitForShell(self, out):
      self.waitFor("> ", out)
    
    def sbt(self, args):
      out = open(self.tmpFile, 'w')
      cmd = " ".join(args)

      self.sbt_i.write(cmd+"\n")
      self.sbt_i.flush()
      res = self.waitFor(".*Total time: .*completed.*", out)
      self.waitForShell(out)
      out.close()
      return self.tmpFile

  sbtCompiler = SBTCompiler()


if not is_vim:

  print sbtCompiler.sbt(ask_user('sbt command:'))
