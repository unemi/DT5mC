PNAME=DT5mCHelp

all: $(PNAME).cshelpindex $(PNAME).helpindex

$(PNAME).cshelpindex : index.html
	hiutil -I corespotlight -Caf $@ -vv .

$(PNAME).helpindex : index.html
	hiutil -I lsm -Caf $@ -vv .

