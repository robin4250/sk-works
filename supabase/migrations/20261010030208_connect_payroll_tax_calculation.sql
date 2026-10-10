-- Refuse to replace unknown calculator or finalization definitions.
do $$ begin
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.refresh_automatic_payroll_internal(uuid,uuid,date)') and md5(prosrc)='f845bd5071801a3502a6b195cf02b9f5' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll tax prerequisite differs: private.refresh_automatic_payroll_internal(uuid,uuid,date)';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('private.apply_payroll_custom_money()') and md5(prosrc)='02807ef140cb91ae1f629ce5cd5f95db' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll tax prerequisite differs: private.apply_payroll_custom_money()';end if;
 if not exists(select 1 from pg_proc where oid=to_regprocedure('payroll_final_private.finalize(uuid,integer,boolean)') and md5(prosrc)='e6b1562ada82bdd99fd350161ae92ca8' and prosecdef and proconfig=array['search_path=""']) then raise exception 'payroll tax prerequisite differs: payroll_final_private.finalize(uuid,integer,boolean)';end if;
end $$;
-- Monthly payroll tax connection. No existing payroll rows are rewritten.
-- Rate data stays in payroll_rate_private; this schema owns only calculation conditions.
create schema payroll_tax_private;
revoke all on schema payroll_tax_private from public,anon,authenticated;
grant usage on schema payroll_tax_private to authenticated;

-- Official numeric reference data; immutable to application roles.
create table payroll_tax_private.monthly_income_rows (
 calendar_year integer not null, lower_yen integer not null, upper_yen integer not null,
 koh integer[] not null check(array_length(koh,1)=8), otsu integer not null,
 primary key(calendar_year,lower_yen),check(lower_yen<upper_yen)
);
alter table payroll_tax_private.monthly_income_rows enable row level security;
revoke all on payroll_tax_private.monthly_income_rows from public,anon,authenticated;
-- Source: https://www.nta.go.jp/publication/pamph/gensen/zeigakuhyo2026/data/01-07.pdf
-- SHA256: c583c9c33cb4e99f4a1505431f2aa768a585b84f09bb9bfb6929b0e8b0c37699
insert into payroll_tax_private.monthly_income_rows values
(2026,105000,107000,array[170,0,0,0,0,0,0,0],3800),
(2026,107000,109000,array[280,0,0,0,0,0,0,0],3800),
(2026,109000,111000,array[380,0,0,0,0,0,0,0],3900),
(2026,111000,113000,array[480,0,0,0,0,0,0,0],4000),
(2026,113000,115000,array[580,0,0,0,0,0,0,0],4100),
(2026,115000,117000,array[680,0,0,0,0,0,0,0],4100),
(2026,117000,119000,array[790,0,0,0,0,0,0,0],4200),
(2026,119000,121000,array[890,0,0,0,0,0,0,0],4300),
(2026,121000,123000,array[990,0,0,0,0,0,0,0],4300),
(2026,123000,125000,array[1090,0,0,0,0,0,0,0],4400),
(2026,125000,127000,array[1190,0,0,0,0,0,0,0],4700),
(2026,127000,129000,array[1300,0,0,0,0,0,0,0],5000),
(2026,129000,131000,array[1400,0,0,0,0,0,0,0],5300),
(2026,131000,133000,array[1500,0,0,0,0,0,0,0],5500),
(2026,133000,135000,array[1600,0,0,0,0,0,0,0],5800),
(2026,135000,137000,array[1710,0,0,0,0,0,0,0],6100),
(2026,137000,139000,array[1810,190,0,0,0,0,0,0],6400),
(2026,139000,141000,array[1910,300,0,0,0,0,0,0],6700),
(2026,141000,143000,array[2010,400,0,0,0,0,0,0],7000),
(2026,143000,145000,array[2110,500,0,0,0,0,0,0],7400),
(2026,145000,147000,array[2220,600,0,0,0,0,0,0],7700),
(2026,147000,149000,array[2320,700,0,0,0,0,0,0],8000),
(2026,149000,151000,array[2420,810,0,0,0,0,0,0],8300),
(2026,151000,153000,array[2520,910,0,0,0,0,0,0],8600),
(2026,153000,155000,array[2620,1010,0,0,0,0,0,0],8900),
(2026,155000,157000,array[2730,1110,0,0,0,0,0,0],9200),
(2026,157000,159000,array[2830,1210,0,0,0,0,0,0],9500),
(2026,159000,161000,array[2910,1300,0,0,0,0,0,0],9800),
(2026,161000,163000,array[2980,1370,0,0,0,0,0,0],10100),
(2026,163000,165000,array[3050,1440,0,0,0,0,0,0],10400),
(2026,165000,167000,array[3120,1510,0,0,0,0,0,0],10700),
(2026,167000,169000,array[3200,1580,0,0,0,0,0,0],11000),
(2026,169000,171000,array[3270,1650,0,0,0,0,0,0],11300),
(2026,171000,173000,array[3340,1730,100,0,0,0,0,0],11500),
(2026,173000,175000,array[3410,1800,170,0,0,0,0,0],11800),
(2026,175000,177000,array[3480,1870,250,0,0,0,0,0],12100),
(2026,177000,179000,array[3550,1940,320,0,0,0,0,0],12500),
(2026,179000,181000,array[3620,2010,390,0,0,0,0,0],12800),
(2026,181000,183000,array[3700,2080,460,0,0,0,0,0],13300),
(2026,183000,185000,array[3770,2150,530,0,0,0,0,0],14000),
(2026,185000,187000,array[3840,2230,600,0,0,0,0,0],14700),
(2026,187000,189000,array[3910,2300,670,0,0,0,0,0],15400),
(2026,189000,191000,array[3980,2370,750,0,0,0,0,0],16100),
(2026,191000,193000,array[4050,2440,820,0,0,0,0,0],16800),
(2026,193000,195000,array[4120,2510,890,0,0,0,0,0],17600),
(2026,195000,197000,array[4200,2580,960,0,0,0,0,0],18300),
(2026,197000,199000,array[4270,2650,1030,0,0,0,0,0],19000),
(2026,199000,201000,array[4340,2730,1100,0,0,0,0,0],19700),
(2026,201000,203000,array[4410,2800,1170,0,0,0,0,0],20400),
(2026,203000,205000,array[4480,2870,1250,0,0,0,0,0],21000),
(2026,205000,207000,array[4550,2940,1320,0,0,0,0,0],21700),
(2026,207000,209000,array[4630,3010,1390,0,0,0,0,0],22500),
(2026,209000,211000,array[4700,3080,1460,0,0,0,0,0],23000),
(2026,211000,213000,array[4770,3150,1530,0,0,0,0,0],23600),
(2026,213000,215000,array[4840,3230,1600,0,0,0,0,0],24100),
(2026,215000,217000,array[4910,3300,1670,0,0,0,0,0],24700),
(2026,217000,219000,array[4980,3370,1750,130,0,0,0,0],25300),
(2026,219000,221000,array[5050,3440,1820,200,0,0,0,0],25800),
(2026,221000,224000,array[5150,3520,1910,300,0,0,0,0],26400),
(2026,224000,227000,array[5250,3630,2020,400,0,0,0,0],27500),
(2026,227000,230000,array[5360,3740,2120,510,0,0,0,0],28500),
(2026,230000,233000,array[5460,3850,2240,610,0,0,0,0],29500),
(2026,233000,236000,array[5570,3950,2340,720,0,0,0,0],30500),
(2026,236000,239000,array[5680,4060,2450,830,0,0,0,0],31500),
(2026,239000,242000,array[5790,4170,2550,940,0,0,0,0],32600),
(2026,242000,245000,array[5890,4280,2660,1040,0,0,0,0],33600),
(2026,245000,248000,array[6000,4380,2770,1150,0,0,0,0],34600),
(2026,248000,251000,array[6110,4490,2880,1260,0,0,0,0],35500),
(2026,251000,254000,array[6220,4590,2980,1370,0,0,0,0],36600),
(2026,254000,257000,array[6320,4710,3090,1470,0,0,0,0],37600),
(2026,257000,260000,array[6430,4810,3200,1580,0,0,0,0],38600),
(2026,260000,263000,array[6530,4920,3310,1680,0,0,0,0],39600),
(2026,263000,266000,array[6650,5020,3410,1800,170,0,0,0],40600),
(2026,266000,269000,array[6750,5140,3520,1900,290,0,0,0],41700),
(2026,269000,272000,array[6860,5240,3620,2010,390,0,0,0],42700),
(2026,272000,275000,array[6960,5350,3740,2110,500,0,0,0],43700),
(2026,275000,278000,array[7080,5450,3840,2230,600,0,0,0],44700),
(2026,278000,281000,array[7180,5560,3950,2330,710,0,0,0],45600),
(2026,281000,284000,array[7290,5670,4050,2440,820,0,0,0],46700),
(2026,284000,287000,array[7390,5780,4170,2540,930,0,0,0],47800),
(2026,287000,290000,array[7500,5880,4270,2650,1030,0,0,0],48900),
(2026,290000,293000,array[7610,5990,4380,2760,1140,0,0,0],50000),
(2026,293000,296000,array[7720,6100,4480,2870,1250,0,0,0],51300),
(2026,296000,299000,array[7820,6210,4590,2970,1360,0,0,0],52400),
(2026,299000,302000,array[7930,6320,4700,3080,1470,0,0,0],53600),
(2026,302000,305000,array[8060,6440,4820,3210,1590,0,0,0],54500),
(2026,305000,308000,array[8180,6570,4940,3330,1720,0,0,0],55200),
(2026,308000,311000,array[8300,6690,5060,3450,1840,210,0,0],56100),
(2026,311000,314000,array[8550,6810,5190,3570,1960,340,0,0],56900),
(2026,314000,317000,array[8790,6930,5310,3700,2080,460,0,0],57700),
(2026,317000,320000,array[9040,7060,5430,3820,2210,580,0,0],58500),
(2026,320000,323000,array[9280,7180,5550,3940,2330,700,0,0],59500),
(2026,323000,326000,array[9530,7300,5680,4060,2450,830,0,0],60500),
(2026,326000,329000,array[9770,7420,5800,4190,2570,950,0,0],61600),
(2026,329000,332000,array[10020,7550,5920,4310,2700,1070,0,0],62600),
(2026,332000,335000,array[10260,7670,6040,4430,2820,1190,0,0],63700),
(2026,335000,338000,array[10510,7790,6170,4550,2940,1320,0,0],64700),
(2026,338000,341000,array[10750,7910,6290,4680,3060,1440,0,0],65800),
(2026,341000,344000,array[11000,8040,6410,4800,3190,1560,0,0],66800),
(2026,344000,347000,array[11240,8160,6530,4920,3310,1680,0,0],67800),
(2026,347000,350000,array[11490,8280,6660,5040,3430,1810,190,0],68800),
(2026,350000,353000,array[11730,8500,6780,5170,3550,1930,320,0],69800),
(2026,353000,356000,array[11980,8750,6900,5290,3680,2050,440,0],70900),
(2026,356000,359000,array[12220,9000,7020,5410,3800,2170,560,0],71900),
(2026,359000,362000,array[12470,9240,7150,5530,3920,2300,680,0],72900),
(2026,362000,365000,array[12710,9490,7270,5660,4040,2420,810,0],73900),
(2026,365000,368000,array[12960,9730,7390,5780,4170,2540,930,0],74900),
(2026,368000,371000,array[13200,9980,7510,5900,4290,2660,1050,0],76000),
(2026,371000,374000,array[13450,10220,7640,6020,4410,2790,1170,0],76900),
(2026,374000,377000,array[13690,10470,7760,6150,4530,2910,1300,0],77800),
(2026,377000,380000,array[13940,10710,7880,6270,4660,3030,1420,0],78700),
(2026,380000,383000,array[14180,10960,8000,6390,4780,3150,1540,0],79600),
(2026,383000,386000,array[14430,11200,8130,6510,4900,3280,1660,0],80600),
(2026,386000,389000,array[14670,11450,8250,6640,5020,3400,1790,170],82000),
(2026,389000,392000,array[14920,11690,8450,6760,5150,3520,1910,300],83600),
(2026,392000,395000,array[15160,11940,8700,6880,5270,3640,2030,420],85400),
(2026,395000,398000,array[15410,12180,8940,7000,5390,3770,2150,540],87100),
(2026,398000,401000,array[15650,12430,9190,7130,5510,3890,2280,660],88700),
(2026,401000,404000,array[15900,12670,9430,7250,5640,4010,2400,790],90500),
(2026,404000,407000,array[16140,12920,9680,7370,5760,4140,2520,910],92200),
(2026,407000,410000,array[16390,13160,9920,7490,5880,4260,2640,1030],93800),
(2026,410000,413000,array[16630,13410,10170,7620,6000,4380,2770,1150],95600),
(2026,413000,416000,array[16880,13650,10410,7740,6130,4500,2890,1280],97300),
(2026,416000,419000,array[17120,13900,10660,7860,6250,4630,3010,1400],98900),
(2026,419000,422000,array[17370,14140,10900,7980,6370,4750,3130,1520],100700),
(2026,422000,425000,array[17610,14390,11150,8110,6490,4870,3260,1640],102400),
(2026,425000,428000,array[17860,14630,11390,8230,6620,4990,3380,1770],104000),
(2026,428000,431000,array[18100,14880,11640,8400,6740,5120,3500,1890],105800),
(2026,431000,434000,array[18350,15120,11880,8650,6860,5240,3620,2010],107500),
(2026,434000,437000,array[18590,15370,12130,8890,6980,5360,3750,2130],109100),
(2026,437000,440000,array[18840,15610,12370,9140,7110,5480,3870,2260],110900),
(2026,440000,443000,array[19080,15860,12620,9380,7230,5610,3990,2380],112600),
(2026,443000,446000,array[19330,16100,12860,9630,7350,5730,4110,2500],114200),
(2026,446000,449000,array[19570,16350,13110,9870,7470,5850,4240,2620],116000),
(2026,449000,452000,array[19860,16590,13350,10120,7600,5970,4360,2750],117600),
(2026,452000,455000,array[20350,16840,13600,10360,7720,6100,4480,2870],119400),
(2026,455000,458000,array[20840,17080,13840,10610,7840,6220,4600,2990],121100),
(2026,458000,461000,array[21330,17330,14090,10850,7960,6340,4730,3110],122700),
(2026,461000,464000,array[21820,17570,14330,11100,8090,6460,4850,3240],124500),
(2026,464000,467000,array[22310,17820,14580,11340,8210,6590,4970,3360],126200),
(2026,467000,470000,array[22800,18060,14820,11590,8360,6710,5090,3480],127800),
(2026,470000,473000,array[23290,18310,15070,11830,8610,6830,5220,3600],129600),
(2026,473000,476000,array[23780,18550,15320,12080,8850,6950,5340,3730],131200),
(2026,476000,479000,array[24270,18800,15560,12320,9100,7080,5460,3850],132800),
(2026,479000,482000,array[24760,19040,15810,12570,9340,7200,5580,3970],134500),
(2026,482000,485000,array[25250,19290,16050,12810,9590,7320,5710,4090],136100),
(2026,485000,488000,array[25740,19530,16300,13060,9830,7440,5830,4220],137600),
(2026,488000,491000,array[26230,19780,16540,13300,10080,7570,5950,4340],139300),
(2026,491000,494000,array[26720,20260,16790,13550,10320,7690,6070,4460],140900),
(2026,494000,497000,array[27210,20750,17030,13790,10570,7810,6200,4580],142500),
(2026,497000,500000,array[27700,21240,17280,14040,10810,7930,6320,4710],144100),
(2026,500000,503000,array[28190,21730,17520,14280,11060,8060,6440,4830],145700),
(2026,503000,506000,array[28680,22220,17770,14530,11300,8180,6570,4950],147300),
(2026,506000,509000,array[29170,22710,18010,14770,11550,8310,6690,5070],149000),
(2026,509000,512000,array[29660,23200,18260,15020,11790,8560,6810,5200],150500),
(2026,512000,515000,array[30150,23690,18500,15260,12040,8800,6930,5320],152100),
(2026,515000,518000,array[30640,24180,18750,15510,12280,9050,7060,5440],153800),
(2026,518000,521000,array[31130,24670,18990,15750,12530,9290,7180,5560],155400),
(2026,521000,524000,array[31620,25160,19240,16000,12770,9540,7300,5690],156900),
(2026,524000,527000,array[32110,25650,19480,16240,13020,9780,7420,5810],158600),
(2026,527000,530000,array[32600,26140,19730,16490,13260,10030,7550,5930],160200),
(2026,530000,533000,array[33090,26630,20160,16730,13510,10270,7670,6050],161600),
(2026,533000,536000,array[33580,27120,20650,16980,13750,10520,7790,6180],163200),
(2026,536000,539000,array[34070,27610,21140,17220,14000,10760,7910,6300],164600),
(2026,539000,542000,array[34560,28100,21630,17470,14240,11010,8040,6420],166000),
(2026,542000,545000,array[35050,28590,22130,17710,14490,11250,8160,6540],167500),
(2026,545000,548000,array[35540,29080,22620,17960,14730,11500,8280,6670],169000),
(2026,548000,551000,array[36030,29570,23110,18200,14980,11740,8500,6790],170500),
(2026,551000,554000,array[36570,30110,23650,18480,15240,12020,8780,6920],171900),
(2026,554000,557000,array[37120,30660,24200,18760,15520,12290,9060,7060],173400),
(2026,557000,560000,array[37670,31210,24750,19030,15790,12570,9330,7200],174900),
(2026,560000,563000,array[38230,31760,25300,19310,16070,12840,9610,7330],176300),
(2026,563000,566000,array[38780,32310,25850,19580,16350,13120,9880,7470],177900),
(2026,566000,569000,array[39330,32870,26400,19930,16620,13400,10160,7610],179300),
(2026,569000,572000,array[39880,33420,26950,20480,16900,13670,10430,7750],180700),
(2026,572000,575000,array[40430,33970,27510,21030,17170,13950,10710,7880],182200),
(2026,575000,578000,array[40980,34520,28060,21580,17450,14220,10990,8030],183700),
(2026,578000,581000,array[41530,35070,28610,22140,17720,14500,11260,8160],185200),
(2026,581000,584000,array[42090,35620,29160,22690,18000,14770,11540,8300],186600),
(2026,584000,587000,array[42640,36170,29710,23240,18280,15050,11810,8580],188100),
(2026,587000,590000,array[43190,36730,30260,23790,18550,15330,12090,8850],189600),
(2026,590000,593000,array[43740,37280,30810,24340,18830,15600,12360,9130],191000),
(2026,593000,596000,array[44290,37830,31370,24890,19100,15880,12640,9400],192600),
(2026,596000,599000,array[44840,38380,31920,25440,19380,16150,12920,9680],194000),
(2026,599000,602000,array[45390,38930,32470,25990,19650,16430,13190,9950],195400),
(2026,602000,605000,array[45950,39480,33020,26550,20080,16700,13470,10230],197000),
(2026,605000,608000,array[46500,40030,33570,27100,20630,16980,13740,10510],198400),
(2026,608000,611000,array[47050,40580,34120,27650,21190,17250,14020,10780],199900),
(2026,611000,614000,array[47600,41140,34670,28200,21740,17530,14290,11060],201300),
(2026,614000,617000,array[48150,41690,35220,28750,22290,17810,14570,11330],202800),
(2026,617000,620000,array[48700,42240,35780,29300,22840,18080,14850,11610],204300),
(2026,620000,623000,array[49250,42790,36330,29850,23390,18360,15120,11880],205700),
(2026,623000,626000,array[49800,43340,36880,30410,23940,18630,15400,12160],207300),
(2026,626000,629000,array[50360,43890,37430,30960,24490,18910,15670,12440],208700),
(2026,629000,632000,array[50910,44440,37980,31510,25050,19180,15950,12710],210100),
(2026,632000,635000,array[51460,45000,38530,32060,25600,19460,16220,12990],211700),
(2026,635000,638000,array[52010,45550,39080,32610,26150,19740,16500,13260],213100),
(2026,638000,641000,array[52560,46100,39640,33160,26700,20240,16780,13540],214600),
(2026,641000,644000,array[53110,46650,40190,33710,27250,20790,17050,13810],215900),
(2026,644000,647000,array[53660,47200,40740,34260,27800,21340,17330,14090],217000),
(2026,647000,650000,array[54220,47750,41290,34820,28350,21890,17600,14370],218000),
(2026,650000,653000,array[54770,48300,41840,35370,28900,22440,17880,14640],219000),
(2026,653000,656000,array[55320,48850,42390,35920,29460,22990,18150,14920],220000),
(2026,656000,659000,array[55870,49410,42940,36470,30010,23540,18430,15190],221000),
(2026,659000,662000,array[56420,49960,43490,37020,30560,24100,18700,15470],222100),
(2026,662000,665000,array[56970,50510,44050,37570,31110,24650,18980,15740],223100),
(2026,665000,668000,array[57520,51060,44600,38120,31660,25200,19260,16020],224100),
(2026,668000,671000,array[58070,51610,45150,38680,32210,25750,19530,16300],225000),
(2026,671000,674000,array[58630,52160,45700,39230,32760,26300,19830,16570],226000),
(2026,674000,677000,array[59180,52710,46250,39780,33320,26850,20380,16850],227100),
(2026,677000,680000,array[59730,53270,46800,40330,33870,27400,20930,17120],228100),
(2026,680000,683000,array[60280,53820,47350,40880,34420,27950,21480,17400],229100),
(2026,683000,686000,array[60830,54370,47910,41430,34970,28510,22030,17670],230100),
(2026,686000,689000,array[61380,54920,48460,41980,35520,29060,22580,17950],231500),
(2026,689000,692000,array[61930,55470,49010,42530,36070,29610,23140,18220],233000),
(2026,692000,695000,array[62490,56020,49560,43090,36620,30160,23690,18500],234500),
(2026,695000,698000,array[63040,56570,50110,43640,37170,30710,24240,18780],236100),
(2026,698000,701000,array[63590,57120,50660,44190,37730,31260,24790,19050],237600),
(2026,701000,704000,array[64140,57680,51210,44740,38280,31810,25340,19330],239100),
(2026,704000,707000,array[64690,58230,51760,45290,38830,32370,25890,19600],240800),
(2026,707000,710000,array[65250,58780,52320,45850,39380,32920,26450,19980],242300),
(2026,710000,713000,array[65860,59390,52930,46470,39990,33530,27070,20590],243800),
(2026,713000,716000,array[66480,60000,53540,47080,40610,34140,27680,21210],245300),
(2026,716000,719000,array[67090,60620,54150,47690,41220,34750,28290,21820],246900),
(2026,719000,722000,array[67700,61230,54770,48300,41830,35370,28900,22430],248400),
(2026,722000,725000,array[68320,61840,55380,48920,42440,35980,29520,23040],250000),
(2026,725000,728000,array[68930,62450,55990,49530,43060,36590,30130,23660],251600),
(2026,728000,731000,array[69540,63070,56600,50140,43670,37210,30740,24270],253100),
(2026,731000,734000,array[70150,63680,57220,50750,44280,37820,31350,24880],254600),
(2026,734000,737000,array[70770,64290,57830,51370,44890,38430,31970,25490],256200),
(2026,737000,740000,array[71380,64900,58440,51980,45510,39040,32580,26110],257700);

create function payroll_tax_private.monthly_income_tax(p_payment_date date,p_after_social bigint,p_column text,p_dependents integer)
returns integer language plpgsql stable security invoker set search_path='' as $$
declare a bigint:=greatest(p_after_social,0); row_tax record; amounts integer[]; base bigint; rate numeric; tax numeric;
begin
 if p_payment_date is null or extract(year from p_payment_date)<>2026 then
  raise exception '支払年の検証済み所得税表がありません' using errcode='22023'; end if;
 if p_after_social is null or p_column is null or p_column not in ('koh','otsu') or p_dependents is null or p_dependents not between 0 and 99 then
  raise exception '所得税区分・扶養人数を確認してください' using errcode='22023'; end if;
 if a<105000 then
  tax:=case when p_column='otsu' then floor(a*0.03063) else 0 end;
 elsif a<740000 then
  select * into strict row_tax from payroll_tax_private.monthly_income_rows where calendar_year=2026 and lower_yen<=a and upper_yen>a;
  tax:=case when p_column='otsu' then row_tax.otsu else row_tax.koh[least(p_dependents,7)+1] end;
 elsif p_column='otsu' then
  tax:=case when a<1710000 then 259200+floor((a-740000)*0.4084) else 655400+floor((a-1710000)*0.45945) end;
 else
  if a<790000 then base:=740000;rate:=0.2042;amounts:=array[71680,65210,58750,52290,45810,39350,32890,26410];
  elsif a<960000 then base:=790000;rate:=0.23483;amounts:=array[81890,75420,68960,62500,56020,49560,43100,36620];
  elsif a<1710000 then base:=960000;rate:=0.33693;amounts:=array[121820,115340,108880,102420,95940,89480,83020,76540];
  elsif a<2130000 then base:=1710000;rate:=0.4084;amounts:=array[374520,368040,361580,355120,348640,342180,335720,329240];
  elsif a<2170000 then base:=2130000;rate:=0.4084;amounts:=array[549440,542970,536500,530040,523570,517110,510640,504170];
  elsif a<2210000 then base:=2170000;rate:=0.4084;amounts:=array[571220,564750,558280,551820,545350,538880,532420,525950];
  elsif a<2250000 then base:=2210000;rate:=0.4084;amounts:=array[593000,586520,580060,573600,567120,560660,554200,547730];
  elsif a<3500000 then base:=2250000;rate:=0.4084;amounts:=array[614770,608300,601840,595380,588900,582440,575980,569500];
  else base:=3500000;rate:=0.45945;amounts:=array[1125270,1118800,1112340,1105880,1099400,1092940,1086480,1080000];end if;
  tax:=amounts[least(p_dependents,7)+1]+floor((a-base)*rate);
 end if;
 -- For otsu the caller supplies only dependents declared on the secondary declaration.
 tax:=greatest(tax-1610*case when p_column='koh' then greatest(p_dependents-7,0) else p_dependents end,0);
 return tax::integer;
end $$;

-- Payroll withholding: exactly 0.50 yen rounds down; >0.50 rounds up.
create function payroll_tax_private.employee_premium(p_base bigint,p_millionths bigint)
returns integer language plpgsql immutable security invoker set search_path='' as $$
begin
 if p_base is null or p_base<0 or p_millionths is null or p_millionths not between 0 and 100000000 then
  raise exception '保険料の計算条件が不正です' using errcode='22023';end if;
 return greatest(ceil(p_base::numeric*p_millionths/100000000-0.5),0)::integer;
end $$;

create table payroll_tax_private.worker_conditions (
 company_id uuid not null,worker_id uuid not null,starts_on date not null,
 version bigint not null check(version>0),value jsonb not null,
 updated_by uuid not null,updated_at timestamptz not null,
 primary key(company_id,worker_id,starts_on),check(starts_on=date_trunc('month',starts_on)::date)
);
create table payroll_tax_private.condition_history (
 company_id uuid not null,worker_id uuid not null,starts_on date not null,version bigint not null,
 before_value jsonb,after_value jsonb not null,actor_id uuid not null,changed_at timestamptz not null,
 primary key(company_id,worker_id,starts_on,version)
);
alter table payroll_tax_private.worker_conditions enable row level security;
alter table payroll_tax_private.condition_history enable row level security;
revoke all on payroll_tax_private.worker_conditions,payroll_tax_private.condition_history from public,anon,authenticated;

create function payroll_tax_private.validate_conditions(v jsonb) returns void
language plpgsql immutable security invoker set search_path='' as $$
declare k text; d date;
begin
 if v is null or jsonb_typeof(v)<>'object' or octet_length(v::text)>4096 or
 v-array['insurance_mode','health','pension','employment','child_support','nursing','birth_date','health_base_yen','pension_base_yen','income_mode','dependents','non_taxable_yen','employment_excluded_yen','additional_social_deduction_yen']<>'{}'::jsonb then
  raise exception '税計算条件が不正です' using errcode='22023';end if;
 if coalesce(v->>'insurance_mode','') not in ('fixed','rates') or coalesce(v->>'income_mode','') not in ('fixed','koh','otsu') then
  raise exception '計算方式を選択してください' using errcode='22023';end if;
 foreach k in array array['health','pension','employment','child_support','nursing'] loop
  if jsonb_typeof(v->k) is distinct from 'boolean' then raise exception '加入条件を確認してください' using errcode='22023';end if;
 end loop;
 foreach k in array array['health_base_yen','pension_base_yen','dependents','non_taxable_yen','employment_excluded_yen','additional_social_deduction_yen'] loop
  if jsonb_typeof(v->k) is distinct from 'number' or (v->>k)!~'^[0-9]{1,9}$' then raise exception '金額・人数は整数で入力してください' using errcode='22023';end if;
 end loop;
 if (v->>'dependents')::integer>99 then raise exception '扶養人数を確認してください' using errcode='22023';end if;
 if v->>'insurance_mode'='rates' then
  if ((v->>'nursing')::boolean or (v->>'child_support')::boolean) and not (v->>'health')::boolean then raise exception '介護保険・支援金の健康保険加入条件を確認してください' using errcode='22023';end if;
  if ((v->>'health')::boolean or (v->>'nursing')::boolean or (v->>'child_support')::boolean) and (v->>'health_base_yen')::integer<=0 then
   raise exception '健康保険の標準報酬月額が必要です' using errcode='22023';end if;
  if (v->>'pension')::boolean and (v->>'pension_base_yen')::integer<=0 then raise exception '厚生年金の標準報酬月額が必要です' using errcode='22023';end if;
  if (v->>'nursing')::boolean then
   if coalesce(v->>'birth_date','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception '介護保険の年齢判定には生年月日が必要です' using errcode='22023';end if;
   d:=(v->>'birth_date')::date;
  end if;
 end if;
 if v->'birth_date' is not null and v->'birth_date'<>'null'::jsonb then
  d:=(v->>'birth_date')::date;
  if d<date '1900-01-01' then raise exception '生年月日を確認してください' using errcode='22023';end if;
 end if;
end $$;

-- Choose the latest revision for the latest applicable deduction month. Future
-- settings cannot overwrite a past period; historical rate evidence is retained.
create function payroll_tax_private.rate_for_month(cid uuid,p_kind text,p_month date)
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('item_id',h.item_id,'version',h.version,'value',h.after_value)
 from payroll_rate_private.history h
 where h.company_id=cid and h.after_value->>'kind'=p_kind
 and (h.after_value->>'payroll_month')::date<=p_month
 order by (h.after_value->>'payroll_month')::date desc,h.version desc limit 1
$$;

create function payroll_tax_private.calculate(cid uuid,wid uuid,p_start date,p_end date,p_gross bigint,p_legacy_deductions bigint)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare profile payroll_tax_private.worker_conditions%rowtype; v jsonb; settings jsonb;
 payday date; additions bigint; gross bigint; social bigint; income bigint; legacy_social bigint; legacy_income bigint;
 premiums jsonb:='{}'; evidence jsonb:='[]'; item jsonb; val jsonb; kind text; flag text; label text;
 base bigint; premium integer; insured_month date; birth date; age_start date; age_end date;
 deduction bigint; taxable bigint; month_offset integer; expected_payment date;
 health_raw numeric:=0; health_rounded integer:=0; health_month date;
begin
 select * into profile from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid and starts_on<=p_start order by starts_on desc limit 1;
 if not found then return null;end if;
 v:=profile.value;perform payroll_tax_private.validate_conditions(v);
 if p_start<>date_trunc('month',p_start)::date or p_end<>(p_start+interval '1 month - 1 day')::date then raise exception '税自動計算は月次給与を対象とします' using errcode='22023';end if;
 select to_jsonb(s) into settings from public.worker_payroll_settings s where company_id=cid and worker_id=wid;
 if settings is null then raise exception '個別給与設定がありません' using errcode='22023';end if;
 legacy_social:=round(coalesce((settings->>'social_insurance_monthly')::numeric,0));
 legacy_income:=round(coalesce((settings->>'income_tax_monthly')::numeric,0));
 payday:=private.payroll_payment_date(p_end,cid,'{}'::jsonb);
 select coalesce(sum(amount_yen) filter(where direction='addition'),0) into additions from public.payroll_adjustments
 where company_id=cid and worker_id=wid and effective_date between p_start and p_end and cancelled_at is null;
 gross:=p_gross+additions;
 if gross<0 or (v->>'income_mode'<>'fixed' and (v->>'non_taxable_yen')::bigint>gross) or (v->>'insurance_mode'='rates' and (v->>'employment')::boolean and (v->>'employment_excluded_yen')::bigint>gross) then
  raise exception '非課税額・雇用保険対象外額が支給額を超えています' using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(coalesce(settings->'custom_deductions','[]')) x where coalesce((x->>'amount_yen')::numeric,0)<>0 and (
 (v->>'insurance_mode'='rates' and trim(x->>'name') in ('健康保険料','社会保険','社会保険料','介護保険料','厚生年金保険','厚生年金保険料','雇用保険料','子ども・子育て支援金')) or
 (v->>'income_mode'<>'fixed' and trim(x->>'name')='所得税'))) then
 raise exception '自由控除に同じ税・保険料があります。二重控除を避けるため確認してください' using errcode='22023';end if;
 if exists(select 1 from public.payroll_adjustments a where a.company_id=cid and a.worker_id=wid and a.effective_date between p_start and p_end and a.cancelled_at is null and a.amount_yen<>0 and (
  (v->>'insurance_mode'='rates' and trim(a.label_snapshot) in ('健康保険料','社会保険','社会保険料','介護保険料','厚生年金保険','厚生年金保険料','雇用保険料','子ども・子育て支援金')) or
  (v->>'income_mode'<>'fixed' and trim(a.label_snapshot)='所得税'))) then
  raise exception '給与調整に同じ税・保険料があります。二重計上を避けるため確認してください' using errcode='22023';end if;
 social:=legacy_social;
 if v->>'insurance_mode'='rates' then
  social:=0;
  foreach kind in array array['health_insurance','nursing_insurance','pension_insurance','employment_insurance','child_support'] loop
   flag:=case kind when 'health_insurance' then 'health' when 'nursing_insurance' then 'nursing' when 'pension_insurance' then 'pension' when 'employment_insurance' then 'employment' else 'child_support' end;
   label:=case kind when 'health_insurance' then '健康保険料' when 'nursing_insurance' then '介護保険料' when 'pension_insurance' then '厚生年金保険' when 'employment_insurance' then '雇用保険料' else '子ども・子育て支援金' end;
   premium:=0;
   if (v->>flag)::boolean then
    item:=payroll_tax_private.rate_for_month(cid,kind,p_start);
    if item is null then raise exception '適用月の料率が未設定です: %',label using errcode='22023';end if;
    val:=item->'value';perform payroll_rate_private.validate_value(val);
    month_offset:=(extract(year from (val->>'insurance_month')::date)::integer-extract(year from (val->>'payroll_month')::date)::integer)*12+extract(month from (val->>'insurance_month')::date)::integer-extract(month from (val->>'payroll_month')::date)::integer;
    insured_month:=(p_start+make_interval(months=>month_offset))::date;
    month_offset:=(extract(year from (val->>'payment_month')::date)::integer-extract(year from (val->>'payroll_month')::date)::integer)*12+extract(month from (val->>'payment_month')::date)::integer-extract(month from (val->>'payroll_month')::date)::integer;
    expected_payment:=(p_start+make_interval(months=>month_offset))::date;
    if expected_payment<>date_trunc('month',payday)::date then raise exception '料率の支払月と会社の給与支払月が一致しません: %',label using errcode='22023';end if;
    base:=case kind when 'pension_insurance' then (v->>'pension_base_yen')::bigint when 'employment_insurance' then gross-(v->>'employment_excluded_yen')::bigint else (v->>'health_base_yen')::bigint end;
    if kind='nursing_insurance' then
     birth:=(v->>'birth_date')::date;
     age_start:=date_trunc('month',birth+interval '40 years'-interval '1 day')::date;
     age_end:=date_trunc('month',birth+interval '65 years'-interval '1 day')::date;
     if insured_month<age_start or insured_month>=age_end then base:=0;end if;
    end if;
    if kind in ('health_insurance','nursing_insurance','child_support') then
     if health_month is not null and health_month<>insured_month then raise exception '健康保険・介護・支援金の適用月が一致しません' using errcode='22023';end if;
     health_month:=insured_month;
     health_raw:=health_raw+base::numeric*(val->>'employee')::bigint/100000000;
     premium:=greatest(ceil(health_raw-0.5),0)::integer-health_rounded;
     health_rounded:=health_rounded+premium;
    else
     premium:=payroll_tax_private.employee_premium(base,(val->>'employee')::bigint);
    end if;
    evidence:=evidence||jsonb_build_array(item||jsonb_build_object('insurance_month',insured_month,'base_yen',base,'employee_yen',premium));
   end if;
   social:=social+premium;premiums:=premiums||jsonb_build_object(label,premium);
  end loop;
 end if;
 taxable:=greatest(gross-(v->>'non_taxable_yen')::bigint-social-(v->>'additional_social_deduction_yen')::bigint,0);
 income:=legacy_income;
 if v->>'income_mode'<>'fixed' then income:=payroll_tax_private.monthly_income_tax(payday,taxable,v->>'income_mode',(v->>'dependents')::integer);end if;
 deduction:=p_legacy_deductions-legacy_income-legacy_social+income+social;
 if deduction<0 then raise exception '控除合計が不整合です' using errcode='22023';end if;
 return jsonb_build_object('calculator_version','payroll-tax-20261010-v1','condition_version',profile.version,'conditions_start',profile.starts_on,'conditions',v,
 'payment_date',payday,'gross_with_adjustments',gross,'income_tax_base_yen',taxable,'income_tax_yen',income,'social_yen',social,'deductions',deduction,
 'premiums',premiums,'rates',evidence,'income_table',case when v->>'income_mode'='fixed' then null else 'nta-monthly-2026-c583c9c3' end);
exception when sqlstate '22023' then
 return jsonb_build_object('calculator_version','payroll-tax-20261010-v1','blocked',true,'reason',sqlerrm,'deductions',p_legacy_deductions,'conditions_start',profile.starts_on,'condition_version',profile.version);
end $$;
revoke all on all functions in schema payroll_tax_private from public,anon,authenticated;

create function payroll_tax_private.read_conditions(cid uuid,wid uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare items jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) or not coalesce(private.payroll_settings_allowed(cid,wid,'view'),false) then
  raise exception 'payroll access denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('starts_on',starts_on,'version',version,'value',value) order by starts_on desc),'[]') into items
 from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid;
 return jsonb_build_object('company_id',cid,'worker_id',wid,'can_edit',coalesce(private.payroll_settings_allowed(cid,wid,'edit'),false),'items',items,'supported_income_years',jsonb_build_array(2026));
end $$;
create function public.read_worker_payroll_tax_conditions(p_company_id uuid,p_worker_id uuid) returns jsonb
language sql security invoker set search_path='' as $$ select payroll_tax_private.read_conditions(p_company_id,p_worker_id) $$;

create function payroll_tax_private.save_conditions(cid uuid,wid uuid,p_start date,p_expected_version bigint,p_value jsonb,p_confirmed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare old_value payroll_tax_private.worker_conditions%rowtype; r record; stamp timestamptz:=clock_timestamp();
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) or not coalesce(private.payroll_settings_allowed(cid,wid,'edit'),false) then
  raise exception 'payroll access denied' using errcode='42501';end if;
 if p_confirmed is not true or p_expected_version is null or p_expected_version<0 or p_start is null or p_start<>date_trunc('month',p_start)::date then
  raise exception '適用月と計算条件の確認が必要です' using errcode='22023';end if;
 perform payroll_tax_private.validate_conditions(p_value);
 -- Same ordering as payroll refresh/finalization. No writes to finalized documents.
 perform 1 from public.companies where id=cid for share;
 perform 1 from public.workers where id=wid and company_id=cid for update;
 if not found then raise exception 'payroll access denied' using errcode='42501';end if;
 select * into old_value from payroll_tax_private.worker_conditions where company_id=cid and worker_id=wid and starts_on=p_start for update;
 if old_value.version=p_expected_version+1 and old_value.value=p_value then return payroll_tax_private.read_conditions(cid,wid);end if;
 if coalesce(old_value.version,0)<>p_expected_version then raise exception '計算条件が更新されています。再読み込みしてください' using errcode='40001';end if;
 insert into payroll_tax_private.worker_conditions values(cid,wid,p_start,p_expected_version+1,p_value,auth.uid(),stamp)
 on conflict(company_id,worker_id,starts_on) do update set version=excluded.version,value=excluded.value,updated_by=excluded.updated_by,updated_at=excluded.updated_at;
 insert into payroll_tax_private.condition_history values(cid,wid,p_start,p_expected_version+1,old_value.value,p_value,auth.uid(),stamp);
 for r in select period_start from public.payroll_statements where company_id=cid and worker_id=wid and period_start>=p_start and workflow_state='draft' and automatic_calculation order by period_start loop
  perform private.refresh_automatic_payroll(cid,wid,r.period_start);
  perform private.sync_payroll_attendance_detail(cid,wid,r.period_start);
  if exists(select 1 from public.payroll_statements where company_id=cid and worker_id=wid and period_start=r.period_start and detail#>>'{tax_calculation,blocked}'='true') then
   raise exception '税計算に必要な料率・対象年・支給条件を確認してください' using errcode='22023';end if;
 end loop;
 return payroll_tax_private.read_conditions(cid,wid);
end $$;
create function public.save_worker_payroll_tax_conditions(p_company_id uuid,p_worker_id uuid,p_starts_on date,p_expected_version bigint,p_value jsonb,p_confirmed boolean) returns jsonb
language sql security invoker set search_path='' as $$ select payroll_tax_private.save_conditions(p_company_id,p_worker_id,p_starts_on,p_expected_version,p_value,p_confirmed) $$;
revoke all on function payroll_tax_private.read_conditions(uuid,uuid),payroll_tax_private.save_conditions(uuid,uuid,date,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function payroll_tax_private.read_conditions(uuid,uuid),payroll_tax_private.save_conditions(uuid,uuid,date,bigint,jsonb,boolean) to authenticated;
revoke all on function public.read_worker_payroll_tax_conditions(uuid,uuid),public.save_worker_payroll_tax_conditions(uuid,uuid,date,bigint,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.read_worker_payroll_tax_conditions(uuid,uuid),public.save_worker_payroll_tax_conditions(uuid,uuid,date,bigint,jsonb,boolean) to authenticated;

-- Retains the resident-tax schedule, paid-leave and canonical refresh behavior.
CREATE OR REPLACE FUNCTION private.refresh_automatic_payroll_internal(cid uuid, wid uuid, day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  start_day date:=date_trunc('month',day)::date;
  end_day date:=(date_trunc('month',day)+interval '1 month - 1 day')::date;
  settings jsonb; resident_source jsonb; a record; current_statement public.payroll_statements%rowtype;
  total numeric:=0; v_deductions numeric:=0; v_custom_deductions numeric:=0; count_rows int:=0;
  category text; allowance text; allowance_index int; seen text[]:='{}'; token text;
  line_detail jsonb; fingerprint text; saved_id uuid; saved_revision int;
  pref record;
  fixed_trade_seen uuid[]:='{}';
  trade_amount numeric;
  expected_gross numeric:=0;
  expected_net numeric:=0;
  tax_result jsonb;
  custom_earnings_total numeric:=0;
  regular_day_base numeric:=0;
  leave_days integer:=0; leave_daily numeric:=0; leave_total numeric:=0;
begin
  perform pg_advisory_xact_lock_shared(hashtextextended(cid::text||':payroll-rate-registry',0));
  perform pg_advisory_xact_lock(hashtextextended(cid::text||wid::text||start_day::text,0));
  select * into current_statement
  from public.payroll_statements
  where company_id=cid and worker_id=wid and period_start=start_day and period_end=end_day
  for update;
  if found and (not current_statement.automatic_calculation or current_statement.workflow_state<>'draft') then return; end if;

  select to_jsonb(s) into settings
  from public.worker_payroll_settings s
  where s.company_id=cid and s.worker_id=wid;

  resident_source := resident_tax_private.resolve(cid,wid,start_day);

  select md5(
    'paid_leave_wage_contract:1'||
    case when resident_source->>'mode'='timeline' then
      coalesce((settings-'updated_at'-'payment_day'-'resident_tax_monthly')::text,'')||resident_source::text
      else coalesce((settings-'updated_at'-'payment_day')::text,'') end||
    coalesce((select jsonb_build_object('payment_day',c.payroll_payment_day,
      'payment_month_offset',c.payroll_payment_month_offset,
      'closing_day',c.payroll_closing_day)::text from public.companies c where c.id=cid),'')||
    coalesce((
      select jsonb_agg(to_jsonb(ae)-'updated_at'-'created_at' order by ae.work_date,ae.id)::text
      from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid
        and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    ),'')||
    coalesce((select jsonb_agg(jsonb_build_object('leave_date',pl.leave_date,'status',pl.status)
      order by pl.leave_date)::text from public.paid_leave_requests pl
      where pl.company_id=cid and pl.worker_id=wid and pl.leave_date between start_day and end_day
        and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date),'')||
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'site_id',scsp.site_id,'source',scsp.source,
          'trade_company_id',scsp.trade_company_id,
          'contract',to_jsonb(ct)-'updated_at'
        )
        order by scsp.site_id
      )::text
      from public.site_calculation_source_preferences scsp
      left join public.trade_company_contracts ct
        on ct.company_id=scsp.company_id and ct.trade_company_id=scsp.trade_company_id
      where scsp.company_id=cid and scsp.output_type='payroll'
    ),'')
  )
  into fingerprint;

  for a in
    select ae.*
    from public.attendance_entries ae
    where ae.company_id=cid and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    order by ae.work_date,ae.id
  loop
    count_rows:=count_rows+1;
    trade_amount:=0;
    pref:=null;

    select scsp.source,tc.id as trade_company_id,
           coalesce(ct.contract_method,'none') as contract_method,
           coalesce(ct.daily_rate_yen,0) as daily_rate_yen,
           coalesce(ct.monthly_rate_yen,0) as monthly_rate_yen,
           coalesce(ct.square_meter_unit_price_yen,0) as square_meter_unit_price_yen,
           coalesce(ct.square_meter_quantity,0) as square_meter_quantity,
           coalesce(ct.contract_amount_yen,0) as contract_amount_yen
    into pref
    from public.site_calculation_source_preferences scsp
    join public.trade_companies tc
      on tc.id=scsp.trade_company_id and tc.company_id=cid
    left join public.trade_company_contracts ct
      on ct.company_id=cid and ct.trade_company_id=tc.id
    where scsp.company_id=cid and scsp.site_id=a.site_id
      and scsp.output_type='payroll'
    limit 1;

    if pref.source='trade_company' then
      if pref.contract_method='daily' then
        trade_amount:=round(coalesce(a.base_man_days,0)*pref.daily_rate_yen);
      elsif pref.contract_method='monthly' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=pref.monthly_rate_yen;
        end if;
      elsif pref.contract_method='square_meter' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=round(pref.square_meter_quantity*pref.square_meter_unit_price_yen);
        end if;
      elsif pref.contract_method='contract' then
        if not pref.trade_company_id=any(fixed_trade_seen) then
          fixed_trade_seen:=array_append(fixed_trade_seen,pref.trade_company_id);
          trade_amount:=pref.contract_amount_yen;
        end if;
      end if;
      total:=total+trade_amount;
    else
      category:=a.work_category;
      total:=total
        + round(coalesce(a.base_man_days,0) * coalesce((settings->>(category||'_daily'))::numeric,0))
        + round(coalesce(a.overtime_hours,0) * coalesce((settings->>(category||'_overtime'))::numeric,0))
        + round(coalesce(a.early_hours,0) * coalesce((settings->>(category||'_early'))::numeric,0));
    end if;

    foreach allowance in array coalesce(a.allowance_names,'{}'::text[]) loop
      token:=a.work_date::text||':'||allowance;
      if token=any(seen) then continue; end if;
      seen:=array_append(seen,token);
      allowance_index:=null;
      if settings is not null then
        select min(i) into allowance_index
        from generate_series(1,3)i
        where nullif(trim(settings->>('allowance_name_'||i)),'')=allowance;
      end if;
      if allowance_index is not null then
        total:=total+round(coalesce((settings->>('allowance_'||allowance_index))::numeric,0));
      end if;
    end loop;
  end loop;

  select count(distinct pl.leave_date) into leave_days
  from public.paid_leave_requests pl
  where pl.company_id=cid and pl.worker_id=wid and pl.status='approved'
    and pl.leave_date between start_day and end_day
    and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
    and not exists(select 1 from public.attendance_entries ae
      where ae.company_id=pl.company_id and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
        and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0
          or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0));
  leave_daily:=private.paid_leave_daily_amount(settings);
  if coalesce(settings->>'pay_type','daily')<>'monthly' then
    leave_total:=leave_days*leave_daily;
    total:=total+leave_total;
  end if;

  -- A registered positive monthly salary is payable independently of attendance.
  -- Daily/hourly approved leave-only months use the configured wage contract.
  if count_rows=0 and leave_days=0 and not (coalesce(settings->>'pay_type','daily')='monthly'
    and coalesce((settings->>'monthly_salary_yen')::numeric,0)>0) then
    if current_statement.id is not null and current_statement.workflow_state='draft' and current_statement.automatic_calculation then
      delete from public.payroll_statements where id=current_statement.id;
    end if;
    return;
  end if;

  if settings is not null then
    total:=total+round(coalesce((settings->>'family_monthly')::numeric,0))
      +round(coalesce((settings->>'transport_monthly')::numeric,0));
    select coalesce(sum(greatest(coalesce((item->>'amount_yen')::integer,0),0)),0)
    into v_custom_deductions
    from jsonb_array_elements(coalesce(settings->'custom_deductions','[]'::jsonb)) item
    where nullif(trim(item->>'name'),'') is not null;

    v_deductions:=round(coalesce((settings->>'income_tax_monthly')::numeric,0))
      +(resident_source->>'amount_yen')::integer
      +round(coalesce((settings->>'social_insurance_monthly')::numeric,0))
      +round(coalesce((settings->>'other_deduction_monthly')::numeric,0))
      +round(v_custom_deductions);
  end if;

  -- Timeline remains a direct tax source even before wage settings exist.
  if settings is null then v_deductions := (resident_source->>'amount_yen')::integer; end if;
  total:=greatest(coalesce(total,0),0);
  v_deductions:=greatest(coalesce(v_deductions,0),0);
  -- Compare the same final amounts that the existing normalization triggers persist.
  -- INSERT/UPDATE below still provide raw attendance totals to those triggers.
  expected_gross:=total;
  if settings->>'pay_type'='monthly' then
    select coalesce(round(sum(coalesce(ae.base_man_days,0)
      *coalesce((settings->>'day_daily')::numeric,0))),0)
    into regular_day_base
    from public.attendance_entries ae
    where ae.company_id=cid and ae.worker_id=wid
      and ae.work_date between start_day and end_day
      and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
      and coalesce(ae.work_category,'day')='day';
    expected_gross:=greatest(expected_gross-regular_day_base
      +round(coalesce((settings->>'monthly_salary_yen')::numeric,0)),0);
  end if;
  select coalesce(sum(greatest(coalesce((item->>'amount_yen')::integer,0),0)),0)
  into custom_earnings_total
  from jsonb_array_elements(coalesce(settings->'custom_earnings','[]'::jsonb)) item
  where nullif(trim(item->>'name'),'') is not null;
  expected_gross:=greatest(expected_gross+custom_earnings_total,0);
  tax_result:=payroll_tax_private.calculate(cid,wid,start_day,end_day,expected_gross::bigint,v_deductions::bigint);
  if tax_result is not null then
    v_deductions:=(tax_result->>'deductions')::numeric;
    fingerprint:=md5(fingerprint||tax_result::text);
  end if;
  expected_net:=greatest(expected_gross-v_deductions,0);
  -- Capture the calculation settings with the generated draft; history is not relabeled later.
  line_detail:=jsonb_build_object(
    'resident_tax_source',resident_source,
    'paid_leave_wage_contract',1,
    '有給単価',leave_daily,
    '有給支給額',leave_total,
    '有給内訳額',leave_days*leave_daily,
    'pay_type',coalesce(settings->>'pay_type','daily'),
    'rate_formula',coalesce(settings->'rate_formula','{}'::jsonb),
    'hourly_rate_yen',coalesce(settings->'hourly_rate_yen','0'::jsonb),
    '出勤日数',coalesce((select sum(coalesce(ae.base_man_days,0)) from public.attendance_entries ae
      where ae.company_id=cid and ae.worker_id=wid and ae.work_date between start_day and end_day
        and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date),0),
    '有給日数',coalesce((select count(*) from public.paid_leave_requests pl
      where pl.company_id=cid and pl.worker_id=wid and pl.leave_date between start_day and end_day
        and pl.leave_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
        and pl.status='approved' and not exists (
      select 1 from public.attendance_entries ae where ae.company_id=pl.company_id
        and ae.worker_id=pl.worker_id and ae.work_date=pl.leave_date
        and (coalesce(ae.base_man_days,0)>0 or coalesce(ae.overtime_hours,0)>0
          or coalesce(ae.early_hours,0)>0 or coalesce(ae.night_hours,0)>0)
    )),0),
    '出勤に基づく支給額',greatest(total-v_deductions,0),
    '計算元選択あり',exists(
      select 1 from public.site_calculation_source_preferences scsp
      where scsp.company_id=cid and scsp.output_type='payroll'
        and scsp.source='trade_company'
        and exists(
          select 1 from public.attendance_entries ae
          where ae.company_id=cid and ae.worker_id=wid
            and ae.site_id=scsp.site_id
            and ae.work_date between start_day and end_day
            and ae.work_date<=(current_timestamp at time zone 'Asia/Tokyo')::date
        )
    )
  );

  if current_statement.id is null then
    insert into public.payroll_statements(
      company_id,worker_id,period_start,period_end,gross_pay,deductions,net_pay,
      detail,workflow_state,approver_ids,automatic_calculation,calculation_blocked,calculation_fingerprint
    )
    values(
      cid,wid,start_day,end_day,total::int,v_deductions::int,greatest(total-v_deductions,0)::int,
      line_detail,'draft',private.payroll_approver_ids(cid),true,false,fingerprint
    )
    returning id,revision into saved_id,saved_revision;
  elsif current_statement.gross_pay is distinct from expected_gross::int
      or current_statement.deductions is distinct from v_deductions::int
      or current_statement.net_pay is distinct from expected_net::int
      or current_statement.calculation_fingerprint is distinct from fingerprint
      or current_statement.calculation_blocked is distinct from coalesce((tax_result->>'blocked')::boolean,false) then
    update public.payroll_statements
    set gross_pay=total::int,
        deductions=v_deductions::int,
        net_pay=greatest(total-v_deductions,0)::int,
        detail=line_detail,
        calculation_fingerprint=fingerprint,
        calculation_blocked=false,
        approved_ids='{}',
        revision=revision+1,
        updated_at=now()
    where id=current_statement.id
    returning id,revision into saved_id,saved_revision;
  end if;

  if saved_id is not null then
    insert into public.payroll_audit(company_id,statement_id,revision,action,actor_id)
    values(cid,saved_id,saved_revision,'automatic_recalculation',auth.uid());
  end if;
end;
$function$;


CREATE OR REPLACE FUNCTION private.apply_payroll_custom_money()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  settings jsonb := '{}'::jsonb;
  tax_result jsonb;
  custom_earnings_total integer := 0;
  custom_deductions_total integer := 0;
  previous_earnings_total integer := 0;
  fixed_deductions_total integer := 0;
  normalized_earnings jsonb := '[]'::jsonb;
  normalized_deductions jsonb := '[]'::jsonb;
  item jsonb;
  item_name text;
  item_amount integer;
  payment_day integer := 25;
begin
  if not new.automatic_calculation or new.workflow_state <> 'draft' then
    return new;
  end if;

  perform pg_advisory_xact_lock_shared(hashtextextended(new.company_id::text||':payroll-rate-registry',0));

  select coalesce(to_jsonb(s),'{}'::jsonb)
  into settings
  from public.worker_payroll_settings s
  where s.company_id=new.company_id
    and s.worker_id=new.worker_id;

  -- Company policy is the only source; legacy worker payment_day is ignored.
  select c.payroll_payment_day into payment_day
  from public.companies c where c.id=new.company_id;
  payment_day:=greatest(least(coalesce(payment_day,25),31),1);

  -- Fresh calculator detail does not contain previously applied named earnings.
  -- Only subtract them for an edit carrying the normalized prior detail.
  if tg_op='UPDATE' and coalesce(new.detail,'{}'::jsonb) ? 'custom_earnings_total' then
    previous_earnings_total :=
      coalesce((old.detail->>'custom_earnings_total')::integer,0);
  end if;

  if jsonb_typeof(settings->'custom_earnings')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_earnings')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null then continue; end if;
      normalized_earnings := normalized_earnings || jsonb_build_array(
        jsonb_build_object('name',item_name,'amount_yen',item_amount)
      );
      custom_earnings_total := custom_earnings_total + item_amount;
    end loop;
  end if;

  if jsonb_typeof(settings->'custom_deductions')='array' then
    for item in
      select value
      from jsonb_array_elements(settings->'custom_deductions')
    loop
      item_name := nullif(trim(item->>'name'),'');
      item_amount := greatest(coalesce((item->>'amount_yen')::integer,0),0);
      if item_name is null then continue; end if;
      normalized_deductions := normalized_deductions || jsonb_build_array(
        jsonb_build_object('name',item_name,'amount_yen',item_amount)
      );
      custom_deductions_total := custom_deductions_total + item_amount;
    end loop;
  end if;

  fixed_deductions_total :=
      round(coalesce((settings->>'income_tax_monthly')::numeric,0))::integer
    + (resident_tax_private.resolve(new.company_id,new.worker_id,new.period_start)->>'amount_yen')::integer
    + round(coalesce((settings->>'social_insurance_monthly')::numeric,0))::integer
    + round(coalesce((settings->>'other_deduction_monthly')::numeric,0))::integer;

  new.gross_pay := greatest(
    coalesce(new.gross_pay,0) - previous_earnings_total + custom_earnings_total,
    0
  );
  new.deductions := greatest(
    fixed_deductions_total + custom_deductions_total,
    0
  );
  new.net_pay := greatest(new.gross_pay - new.deductions,0);
  new.detail := (
    coalesce(new.detail,'{}'::jsonb)
      - '勤続手当'
      - '役職手当'
      - '働き方手当'
      - '介護保険料'
      - '厚生年金保険'
      - '雇用保険料'
      - 'SKB会費'
  ) || jsonb_build_object(
    'resident_tax_source',resident_tax_private.resolve(new.company_id,new.worker_id,new.period_start),
    '家族手当',round(coalesce((settings->>'family_monthly')::numeric,0))::integer,
    'custom_earnings',normalized_earnings,
    'custom_deductions',normalized_deductions,
    'custom_earnings_total',custom_earnings_total,
    '支払日',payment_day
  );

  tax_result:=payroll_tax_private.calculate(new.company_id,new.worker_id,new.period_start,new.period_end,new.gross_pay,new.deductions);
  if tax_result->>'blocked'='true' then
    new.calculation_blocked:=true;
    new.detail:=new.detail||jsonb_build_object('tax_calculation',tax_result);
  elsif tax_result is not null then
    new.deductions:=(tax_result->>'deductions')::integer;
    new.net_pay:=greatest(new.gross_pay-new.deductions,0);
    new.detail:=new.detail||jsonb_build_object('所得税',(tax_result->>'income_tax_yen')::integer,'tax_calculation',tax_result);
    if tax_result#>>'{conditions,insurance_mode}'='rates' then
      new.detail:=(new.detail-array['社会保険','健康保険料','介護保険料','厚生年金保険','雇用保険料','子ども・子育て支援金'])||(tax_result->'premiums');
    else
      new.detail:=new.detail||jsonb_build_object('社会保険',(tax_result->>'social_yen')::integer);
    end if;
  else
    new.detail:=new.detail-'tax_calculation';
  end if;
  return new;
end
$function$;

-- Freeze the exact selected rates, tax reference and conditions with the document.
create or replace function payroll_final_private.finalize(p_statement_id uuid,p_expected_revision integer,p_confirmed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare initial public.payroll_statements%rowtype; ps public.payroll_statements%rowtype;
 saved payroll_final_private.documents%rowtype; settings jsonb; adjustments jsonb; adjustment_detail jsonb;
 additions bigint; removals bigint; doc jsonb; value jsonb; stamp timestamptz:=clock_timestamp();
 company_name text; worker_name text; bank jsonb;
begin
 if auth.uid() is null or not coalesce(private.account_access_allowed(),false) then raise exception 'payroll access denied'; end if;
 if p_confirmed is not true then raise exception 'explicit finalization confirmation required'; end if;
 select * into initial from public.payroll_statements where id=p_statement_id;
 if not found or not coalesce(private.payroll_settings_allowed(initial.company_id,initial.worker_id,'edit'),false) then raise exception 'payroll access denied'; end if;
 perform 1 from public.companies where id=initial.company_id for share;
 if not found then raise exception 'payroll access denied'; end if;
 perform 1 from public.workers where id=initial.worker_id and company_id=initial.company_id for share;
 if not found then raise exception 'payroll access denied'; end if;
 if initial.period_start is null or initial.period_end is null or initial.period_start<>date_trunc('month',initial.period_start)::date or initial.period_end<>(initial.period_start+interval '1 month - 1 day')::date then raise exception 'only canonical monthly payroll periods can be finalized'; end if;
 perform pg_advisory_xact_lock(hashtextextended(initial.company_id::text||initial.worker_id::text||initial.period_start::text,0));
 select * into ps from public.payroll_statements where id=p_statement_id for update;
 if not found or (ps.company_id,ps.worker_id,ps.period_start,ps.period_end) is distinct from (initial.company_id,initial.worker_id,initial.period_start,initial.period_end) then raise exception 'payroll scope changed'; end if;
 select * into saved from payroll_final_private.documents where statement_id=ps.id;
 if found then
  if ps.workflow_state<>'finalized' or saved.revision is distinct from p_expected_revision then raise exception 'payroll revision conflict'; end if;
  return jsonb_build_object('finalized',true,'revision',saved.revision,'snapshot',jsonb_set(saved.value,'{detail,bank_account}','{}'::jsonb));
 end if;
 if not ps.automatic_calculation or ps.workflow_state<>'draft' then raise exception 'only automatic draft can be finalized; legacy finalization is not backfilled'; end if;
 if p_expected_revision is null or ps.revision is distinct from p_expected_revision then raise exception 'payroll revision conflict'; end if;
 perform private.refresh_automatic_payroll_internal(ps.company_id,ps.worker_id,ps.period_start);
 perform private.sync_payroll_attendance_detail(ps.company_id,ps.worker_id,ps.period_start);
 select * into ps from public.payroll_statements where id=p_statement_id;
 if ps.revision is distinct from p_expected_revision then return jsonb_build_object('finalized',false,'reason','recalculation_changed','revision',ps.revision); end if;
 if ps.calculation_blocked then raise exception 'payroll calculation blocked'; end if;
 if not coalesce(private.payroll_confirmed_all(ps.id),false) or exists(
  select 1 from public.payroll_confirmers c left join public.payroll_statement_reviews r on r.statement_id=ps.id and r.reviewer_id=c.user_id
  where c.company_id=ps.company_id and (r.checked_revision is distinct from ps.revision or r.confirmed_revision is distinct from ps.revision or r.confirmed_at is null)
 ) then raise exception 'all current revision reviews required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'label',a.label_snapshot,'direction',a.direction,'amount_yen',a.amount_yen,'effective_date',a.effective_date) order by a.effective_date,a.id),'[]'),
 coalesce(sum(a.amount_yen) filter(where a.direction='addition'),0),coalesce(sum(a.amount_yen) filter(where a.direction='deduction'),0)
 into adjustments,additions,removals from public.payroll_adjustments a where a.company_id=ps.company_id and a.worker_id=ps.worker_id and a.effective_date between ps.period_start and ps.period_end and a.cancelled_at is null;
 select coalesce(jsonb_object_agg(label,total),'{}') into adjustment_detail from (
  select a.label_snapshot label,sum(case when a.direction='addition' then a.amount_yen else -a.amount_yen end)::integer total from public.payroll_adjustments a
  where a.company_id=ps.company_id and a.worker_id=ps.worker_id and a.effective_date between ps.period_start and ps.period_end and a.cancelled_at is null group by a.label_snapshot
 ) grouped;
 select c.name,w.name into company_name,worker_name from public.companies c join public.workers w on w.company_id=c.id where c.id=ps.company_id and w.id=ps.worker_id;
 select coalesce(to_jsonb(s)-array['company_id','worker_id','created_by','updated_by','created_at','updated_at'],'{}') into settings from public.worker_payroll_settings s where s.company_id=ps.company_id and s.worker_id=ps.worker_id;
 select jsonb_build_object('bank_name',b.bank_name,'branch_name',b.branch_name,'account_type',b.account_type,'account_number',b.account_number,'account_holder',b.account_holder) into bank from public.worker_private_bank_accounts b where b.company_id=ps.company_id and b.worker_id=ps.worker_id order by b.updated_at desc nulls last limit 1;
 doc:=private.payroll_document_metadata(ps.id);
 value:=jsonb_build_object('schema_version',1,'calculator_version',coalesce(ps.detail#>>'{tax_calculation,calculator_version}','resident-tax-20261009161427'),'statement_id',ps.id,'revision',ps.revision,
 'period_start',ps.period_start,'period_end',ps.period_end,'issued_at',ps.issued_at,'company_name',company_name,'worker_name',worker_name,
 'base_result',jsonb_build_object('gross_pay',ps.gross_pay,'deductions',ps.deductions,'net_pay',ps.net_pay),
 'result',jsonb_build_object('gross_pay',(ps.gross_pay+additions)::integer,'deductions',(ps.deductions+removals)::integer,'net_pay',(ps.gross_pay+additions-ps.deductions-removals)::integer),
 'conditions',jsonb_build_object('settings',coalesce(settings,'{}'),'resident_tax',resident_tax_private.resolve(ps.company_id,ps.worker_id,ps.period_start),'family_allowance_mode','legacy_fixed','company_rate_registry_adopted',coalesce(ps.detail#>>'{tax_calculation,conditions,insurance_mode}'='rates',false),'income_tax_table_registry_adopted',false,'income_tax_official_catalog',ps.detail#>'{tax_calculation,income_table}','tax_calculation',ps.detail->'tax_calculation'),
 'adjustments',adjustments,'document_metadata',doc,'detail',coalesce(ps.detail,'{}')||adjustment_detail||jsonb_build_object('bank_account',coalesce(bank,'{}'),'workflow_state','finalized','revision',ps.revision,'review_confirmed',true,'reviewed_at',(select max(r.confirmed_at) from public.payroll_statement_reviews r join public.payroll_confirmers pc on pc.company_id=ps.company_id and pc.user_id=r.reviewer_id where r.statement_id=ps.id and r.confirmed_revision=ps.revision))||doc,
 'finalized_by',auth.uid(),'finalized_at',stamp);
 insert into payroll_final_private.documents values(ps.id,ps.company_id,ps.worker_id,ps.period_start,ps.period_end,ps.revision,value,auth.uid(),stamp);
 update public.payroll_statements set workflow_state='finalized',finalized_by=auth.uid(),finalized_at=stamp where id=ps.id;
 insert into payroll_final_private.history(statement_id,company_id,worker_id,revision,actor_id,changed_at,value) values(ps.id,ps.company_id,ps.worker_id,ps.revision,auth.uid(),stamp,value);
 return jsonb_build_object('finalized',true,'revision',ps.revision,'snapshot',jsonb_set(value,'{detail,bank_account}','{}'::jsonb));
end $$;
