#! /usr/bin/env python
# encoding: utf-8
# WARNING! Do not edit! https://waf.io/book/index.html#_obtaining_the_waf_file

from waflib import Logs,TaskGen,Task,Build,Scripting
Task.Task.keep_last_cmd=True
class ClangDbContext(Build.BuildContext):
	'''generates compile_commands.json by request'''
	cmd='clangdb'
	def write_compilation_database(self):
		database_file=self.bldnode.make_node('compile_commands.json')
		Logs.info('Build commands will be stored in %s',database_file.path_from(self.path))
		try:
			root=database_file.read_json()
		except IOError:
			root=[]
		clang_db=dict((x['file'],x)for x in root)
		for task in self.clang_compilation_database_tasks:
			try:
				cmd=task.last_cmd
			except AttributeError:
				continue
			f_node=task.inputs[0]
			filename=f_node.path_from(task.get_cwd())
			entry={"directory":task.get_cwd().abspath(),"arguments":cmd,"file":filename,}
			clang_db[filename]=entry
		root=list(clang_db.values())
		database_file.write_json(root)
	def execute(self):
		self.restore()
		self.cur_tasks=[]
		self.clang_compilation_database_tasks=[]
		if not self.all_envs:
			self.load_envs()
		self.recurse([self.run_dir])
		self.pre_build()
		def exec_command(self,*k,**kw):
			return 0
		for g in self.groups:
			for tg in g:
				try:
					f=tg.post
				except AttributeError:
					pass
				else:
					f()
				if isinstance(tg,Task.Task):
					lst=[tg]
				else:lst=tg.tasks
				for tsk in lst:
					if tsk.__class__.__name__=="swig":
						tsk.runnable_status()
						if hasattr(tsk,'more_tasks'):
							lst.extend(tsk.more_tasks)
					tup=tuple(y for y in[Task.classes.get(x)for x in('c','cxx')]if y)
					if isinstance(tsk,tup):
						self.clang_compilation_database_tasks.append(tsk)
						tsk.nocache=True
						old_exec=tsk.exec_command
						tsk.exec_command=exec_command
						tsk.run()
						tsk.exec_command=old_exec
		self.write_compilation_database()
EXECUTE_PATCHED=False
def patch_execute():
	global EXECUTE_PATCHED
	if EXECUTE_PATCHED:
		return
	def new_execute_build(self):
		if self.cmd.startswith('build'):
			Scripting.run_command(self.cmd.replace('build','clangdb'))
		old_execute_build(self)
	old_execute_build=getattr(Build.BuildContext,'execute_build',None)
	setattr(Build.BuildContext,'execute_build',new_execute_build)
	EXECUTE_PATCHED=True
patch_execute()
