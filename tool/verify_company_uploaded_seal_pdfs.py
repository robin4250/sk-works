from pathlib import Path
import subprocess
root=Path('build/company-uploaded-seal-proof')
for name in ('invoice','payroll','payment','order','acceptance'):
    path=root/(name+'.pdf')
    result=subprocess.run(['pdfimages','-list',str(path)],capture_output=True,text=True,check=True)
    rows=[line.split() for line in result.stdout.splitlines() if line.strip() and line.split()[0].isdigit()]
    assert any(len(row)>4 and row[2]=='image' and row[3:5]==['32','32'] for row in rows),name+' frozen PNG missing'
    assert any(len(row)>4 and row[2]=='smask' and row[3:5]==['32','32'] for row in rows),name+' transparency missing'
print('PASS frozen PNG image and alpha mask in all five production PDF paths')
