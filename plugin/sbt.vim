exec scriptmanager#DefineAndBind('s:c','g:vim_addon_sbt', '{}')
exec scriptmanager#DefineAndBind('s:b','s:c["sbt_features"]', '{}')

" sbt-launch-*.jar location
if !exists('*SBT_JAR')
  fun! SBT_JAR()
    " assume that if sbt exists that it is a script which contains the .jar
    " location (linux only!)
    if executable('sbt')
      let script = system('which sbt')
      let lines = readfile(substitute(script,'[\r\n]','','g'))
      if lines[0] =~ '^#!'
        return  matchstr(join(lines,"\n"), '\zs[^ \t\r\n]*sbt-launch[^ \t\r\n]*.jar\>\ze')
      endif
    endif
    echoe "Can't find sbt-launch-*.jar. Please define SBT_JAR in your ~/.vimrc. It should return the jar location"
  endf
endif

if !exists('g:sbt')
  " assume that this executable exists
  let g:sbt = "sbt"
endif

" TODO
call actions#AddAction('run sbt with bg#RunQF'                    , {'action': funcref#Function('sbt#CompileRHS',{'args':[0,["compile"]]})})
call actions#AddAction('run sbt with bg process (requires python)', {'action': funcref#Function('sbt#CompileRHS',{'args':[1,["compile"]]})})

" run a sbt command manually
command -nargs=* SBT call sbt#RunCommand([<f-args>])

command -nargs=* -complete=file ScalaExceptionTraceToQuickFix call sbt#ScalaExceptionTraceToQuickFix(<f-args>)
command -nargs=* -complete=customlist,sbt#AddFeatureCmdCompletion SBTAddFeature call sbt#AddFeature(<f-args>)
command -nargs=0 SBTOpenBuildAndPluginfiles exec 'n project/build/*.scala | n project/plugins/*.scala'

if get(s:c,'setup_default_sbt_features',1)
  " snippets to be added to .scala files to enable those features
  " allowed keys:
  "
  "  plugins_imports
  "  plugins_with
  "  plugins_code
  "
  "  build_imports
  "  build_with
  "  build_code
  "
  "  build: add to project/build/*.scala file
  "  plugins: add to project/plugins/*.scala file
  "
  "  implementation details see SbtAddFeature

  if !has_key(s:b, 'sbteclipsify')
    let s:b['sbteclipsify'] = {
      \  'plugins_code': ['lazy val eclipse = "de.element34" % "sbt-eclipsify" % "0.5.3"']
      \ ,'build_imports' : ['import de.element34.sbteclipsify._']
      \ ,'build_with' : ['with Eclipsify']
      \ }
  endif
  if !has_key(s:b, 'sbtidea')
    let s:b['sbtidea'] = {
      \  'plugins_code': [
      \     'val repo = "GH-pages repo" at "http://mpeltonen.github.com/maven/"'
      \    ,'val idea = "com.github.mpeltonen" % "sbt-idea-plugin" % "0.1-SNAPSHOT"'
      \    ]
      \ ,'build_with' : ['with IdeaProject']
      \ }
  endif
  if !has_key(s:b, 'executable_archive')
    let s:b['executable_archive'] = {
      \  'plugins_code': ['val extract = "org.scala-tools.sbt" % "installer-plugin" % "0.3.0"']
      \ ,'build_with' : ['with extract.BasicSelfExtractingProject']
      \ ,'build_code' : [' // many lines missing here .. I"ll refactor this if you need it. Contact me :-)']
      \ }
  endif
  if !has_key(s:b, 'codefellow')
    let s:b['codefellow'] = {
      \  'plugins_code': ['val codefellow = "de.tuxed" % "codefellow-plugin" % "0.3"']
      \ ,'build_with': ['with de.tuxed.codefellow.plugin.CodeFellowPlugin']
      \ }
  endif
endif
