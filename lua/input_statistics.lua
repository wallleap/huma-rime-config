-- github.com/amzxyz
-- 一个用于统计输入字数和其他时间维度的统计。
-- 触发方式：日统计"tjrt"、周统计"tjzt"、月统计"tjyt"、年统计"tjnt"、统计清空"tjqk"。
-- 在方案文件中添加以下字段：
-- engine:
--   translators:
--     - lua_translator@*input_statistics                  # 统计不同方案不同维度下输入信息
--
-- recognizer:
--   patterns:
--     stats: "^tj(rt|zt|yt|nt|qk)$"                    # 统计输入信息识别模式

local input_stats = input_stats or {
  daily = { count = 0, length = 0, fastest = 0, ts = 0 },
  weekly = { count = 0, length = 0, fastest = 0, ts = 0 },
  monthly = { count = 0, length = 0, fastest = 0, ts = 0 },
  yearly = { count = 0, length = 0, fastest = 0, ts = 0 },
  lengths = {},
  daily_max = 0,
  recent = {},
  yesterday = { count = 0, length = 0, fastest = 0, ts = 0 } -- 新增昨日数据存储
}

-- 优美诗句（两行显示）
local chicken_soups = {
  "『人生如逆旅，\n   我亦是行人。』\n《临江仙》\n	——苏轼",
  "『大漠孤烟直，\n   长河落日圆。』\n《使至塞上》\n	——王维",
  "『春水碧于天，\n   画船听雨眠。』\n《菩萨蛮》\n	——韦庄",
  "『行到水穷处，\n   坐看云起时。』\n《终南别业》\n	——王维",
  "『世界微尘里，\n   吾宁爱与憎。』\n《北青萝》\n	——李商隐",
  "『当时明月在，\n   曾照彩云归。』\n《临江仙》\n	——晏几道",
  "『晚来天欲雪，\n   能饮一杯无？』\n《问刘十九》\n	——白居易",
  "『草木有本心，\n   何求美人折？』\n《感遇十二首·其一》\n	——张九龄",
  "『水晶帘动微风起，\n   满架蔷薇一院香。』\n《山亭夏日》\n	——高骈",
  "『银烛秋光冷画屏，\n   轻罗小扇扑流萤。』\n《秋夕》\n	——杜牧",
  "『醉后不知天在水，\n   满船清梦压星河。』\n《题龙阳县青草湖》\n	——唐珙",
  "『疏影横斜水清浅，\n   暗香浮动月黄昏。』\n《山园小梅》\n	——林逋",
  "『春风得意马蹄疾，\n   一日看尽长安花。』\n《登科后》\n	——孟郊",
  "『长风破浪会有时，\n   直挂云帆济沧海。』\n《行路难·其一》\n	——李白",
  "『落霞与孤鹜齐飞，\n   秋水共长天一色。』\n《滕王阁序》\n	——王勃",
  "『纸上得来终觉浅，\n   绝知此事要躬行。』\n《冬夜读书示子聿》\n	——陆游",
  "『从此无心爱良夜，\n   任他明月下西楼。』\n《写情》\n	——李益",
  "『问渠那得清如许？\n   为有源头活水来。』\n《观书有感·其一》\n	——朱熹",
  "『不畏浮云遮望眼，\n   只缘身在最高层。』\n《登飞来峰》\n	——王安石",
  "『玲珑骰子安红豆，\n   入骨相思知不知。』\n《新添声杨柳枝词》\n	——温庭筠",
  "『沉舟侧畔千帆过，\n   病树前头万木春。』\n《酬乐天扬州初逢席上见赠》\n	——刘禹锡",
  "『相恨不如潮有信，\n   相思始觉海非深。』\n《浪淘沙·借问江潮与海水》\n	——白居易",
  "『朱弦一拂余音在，\n   却是当时寂寞心。』\n《论诗三十首·其二十》\n	——元好问",
  "『玲珑骰子安红豆，\n   入骨相思知不知。』\n《新添声杨柳枝词》\n	——温庭筠",
  "『海棠未雨，梨花先雪，一半春休。』\n《眼儿媚》\n	——王雱",
  "『一重山，两重山。山远天高烟水寒。』\n《长相思》\n	——李煜",
  "『晓看天色暮看云，行也思君，坐也思君。』\n《一剪梅》\n	——唐寅",
  "曾经沧海难为水，\n除却巫山不是云。\n——元稹\n《离思五首·其四》",
  "山无陵，\n江水为竭，\n冬雷震震，\n夏雨雪，\n天地合，\n乃敢与君绝。\n——佚名",
  "只愿君心似我心，\n定不负相思意。\n——李之仪\n《卜算子》",
  "身无彩凤双飞翼，\n心有灵犀一点通。\n——李商隐\n《无题》",
  "愿得一心人，\n白头不相离。\n——卓文君\n《白头吟》",
  "问世间，\n情是何物，\n直教生死相许？\n——元好问\n《摸鱼儿·雁丘词》",
  "换我心，\n为你心，\n始知相忆深。\n——顾夐\n《诉衷情》",
  "关关雎鸠，\n在河之洲。\n窈窕淑女，\n君子好逑。\n——佚名\n《关雎》",
  "云中谁寄锦书来？雁字回时，\n月满西楼。\n——李清照\n《一剪梅》",
  "在天愿作比翼鸟，\n在地愿为连理枝。\n——白居易\n《长恨歌》",
  "青山一道同云雨，\n明月何曾是两乡。\n——王昌龄\n《送柴侍御》",
  "桃李春风一杯酒，\n江湖夜雨十年灯。\n——黄庭坚\n《寄黄几复》",
  "莫愁前路无知己，\n天下谁人不识君。\n——高适\n《别董大二首》",
  "海内存知己，\n天涯若比邻。\n——王勃\n《送杜少府之任蜀州》",
  "何日功成名遂了，\n还乡，\n醉笑陪公三万场。\n——苏轼\n《南乡子·和杨元素时移守密州》",
  "故人入我梦，\n明我长相忆。\n——杜甫\n《梦李白二首·其一》",
  "同心一人去，\n坐觉长安空。\n——白居易\n《别元九后咏所怀》",
  "遥知湖上一樽酒，\n 能忆天涯万里人。\n——欧阳修\n《春日西湖寄谢法曹歌》",
  "不辞山路远，\n踏雪也相过。\n——张九龄\n《答陆澧》",
  "我见君来，\n顿觉吾庐，\n溪山美哉。\n——辛弃疾\n《沁园春·和吴尉子似》",
  "宁可枝头抱香死，\n何曾吹落北风中。\n——郑思肖\n《画菊》",
  "时人不识凌云木，\n直待凌云始道高。\n——杜荀鹤\n《小松》",
  "白日不到处，\n青春恰自来。\n苔花如米小，\n也学牡丹开。\n——袁枚\n《苔》",
  "不经一番寒彻骨，\n怎得梅花扑鼻香。\n——黄蘖禅师\n《上堂开示颂》",
  "竹杖芒鞋轻胜马，\n谁怕？一蓑烟雨任平生。\n——苏轼\n《定风波》",
  "疾风知劲草，\n板荡识诚臣。\n——李世民\n《赐萧瑀》",
  "读书破万卷，\n下笔如有神。\n——杜甫\n《奉赠韦左丞丈二十二韵》",
  "千淘万漉虽辛苦，\n吹尽狂沙始到金。\n——刘禹锡\n《浪淘沙·其八》",
  "大鹏一日同风起，\n扶摇直上九万里。\n——李白\n《上李邕》",
  "老骥伏枥，\n志在千里。\n烈士暮年，\n壮心不已。\n——曹操\n《龟虽寿 》",
  "人言落日是天涯，\n望极天涯不见家。\n——李觏\n《乡思》",
  "露从今夜白，\n月是故乡明。\n——杜甫\n《月夜忆舍弟》",
  "风一更，\n雪一更，\n聒碎乡心梦不成，\n故园无此声。\n——纳兰性德\n《长相思·山一程》",
  "离别家乡岁月多，\n近来人事半消磨。\n——贺知章\n《回乡偶书二首》",
  "借问梅花何处落，\n风吹一夜满关山。\n——高适\n《塞上听吹笛》",
  "浊酒一杯家万里，\n燕然未勒归无计。\n——范仲淹\n《渔家傲·秋思》",
  "一年将尽夜，\n万里未归人。\n——戴叔伦\n《除夜宿石头驿》",
  "一叫一回肠一断，\n三春三月忆三巴。\n——李白\n《宣城见杜鹃花》",
  "天涯倦客，\n山中归路，\n望断故园心眼。\n——苏轼\n《永遇乐·彭城夜宿燕子楼》",
  "何日归家洗客袍？银字笙调，\n心字香烧。\n——蒋捷\n《一剪梅·舟过吴江》",
  "近水楼台先得月，\n向阳花木易为春。\n——苏麟\n《断句》",
  "梅须逊雪三分白，\n雪却输梅一段香。\n——卢梅坡\n《雪梅·其一》",
  "莫道桑榆晚，\n为霞尚满天。\n——刘禹锡\n《酬乐天咏老见示》",
  "天生我材必有用，\n千金散尽还复来。\n——李白\n《将进酒》",
  "试玉要烧三日满，\n辨材须待七年期。\n——白居易\n《放言五首·其三》",
  "江山代有才人出，\n各领风骚数百年。\n——赵翼\n《论诗五首·其二》",
  "疾风知劲草，\n板荡识诚臣。\n——李世民\n《赐萧瑀》",
  "时来天地皆同力，\n运去英雄不自由。\n——罗隐\n《筹笔驿》",
  "富贵必从勤苦得，\n男儿须读五车书。\n——杜甫\n《柏学士茅屋》",
  "居高声自远，\n非是藉秋风。\n——虞世南\n《蝉》",
  "知我者，\n谓我心忧；\n不知我者，\n谓我何求。\n《王风·黍离》",
  "手如柔荑，\n肤如凝脂，\n领如蝤蛴，\n齿如瓠犀，\n螓首蛾眉，\n巧笑倩兮，\n美目盼兮。,",
  "蒹葭苍苍，\n白露为霜。\n所谓伊人，\n在水一方。\n——《秦风·蒹葭》",
  "五月斯螽动股，\n六月莎鸡振羽，\n七月在野，\n八月在宇，\n九月在户，\n十月蟋蟀入我床下。\n",
  "昔我往矣，\n杨柳依依。\n今我来思，\n雨雪霏霏。\n——《小雅·采薇》",
  "投我以桃，\n报之以李。\n——\n《大雅·抑》",
  "死生契阔，\n与子成说。\n执子之手，\n与子偕老。\n——《邶风·击鼓》",
  "靡不有初，\n鲜克有终。\n——《大雅·荡》",
  "桃之夭夭，\n灼灼其华。\n之子与归，\n宜其室家。\n——《周南·桃夭》",
  "今人不见古时月，\n今月曾经照古人。\n——李白\n《把酒问月·故人贾淳令予问之》",
  "海上生明月，\n天涯共此时。\n——张九龄\n《望月怀远》",
  "举杯邀明月，\n对影成三人。\n——李白\n《月下独酌四首·其一》",
  "江畔何人初见月？江月何年初照人？——张若虚\n《春江花月夜》",
  "月儿弯弯照九州，\n几家欢乐几家愁。\n——佚名\n《月儿弯弯照九州》",
  "明月皎皎照我床，\n星汉西流夜未央。\n——曹丕\n《燕歌行二首·其一》",
  "明月不知君已去，\n夜深还照读书窗。\n——刘子翚\n《绝句送巨山》",
  "素月分辉，\n明河共影，\n表里俱澄澈。\n——张孝祥\n《念奴娇·过洞庭》",
  "辛苦最怜天上月，\n一昔如环，\n昔昔都成玦。\n——纳兰性德\n《蝶恋花》",
  "愿我如星君如月，\n夜夜流光相皎洁。\n——范成大\n《车遥遥篇》",
  "新竹高于旧竹枝，\n全凭老干为扶持。\n——郑燮\n《新竹》",
  "惟将终夜长开眼，\n报答平生未展眉。\n——元稹\n《遣悲怀三首·其三》",
  "谁言寸草心，\n报得三春晖。\n——孟郊\n《游子吟 》",
  "曾为大梁客，\n不负信陵恩。\n——王昌龄\n《答武陵太守》",
  "低徊愧人子，\n不敢叹风尘。\n——蒋士铨\n《岁暮到家》",
  "西风满天雪，\n何处报人恩。\n——齐己\n《剑客》",
  "剧辛乐毅感恩分，\n输肝剖胆效英才。\n——李白\n《行路难三首》",
  "自蒙半夜传衣后，\n不羡王祥得佩刀。\n——李商隐\n《谢书》",
  "遥想吾师行道处，\n天香桂子落纷纷。\n——白居易\n《寄韬光禅师》",
  "十五彩衣年，\n承欢慈母前。\n——孟浩然\n《送张参明经举兼向泾州觐省》",
  "落霞与孤鹜齐飞，\n秋水共长天一色。\n——王勃\n《滕王阁序》",
  "星垂平野阔，\n月涌大江流。\n——杜甫\n《旅夜书怀》",
  "水光潋滟晴方好，\n山色空蒙雨亦奇。\n——苏轼\n《饮湖上初晴后雨二首·其二》",
  "西塞山前白鹭飞，\n桃花流水鳜鱼肥。\n——张志和\n《渔歌子》",
  "山黛远，\n月波长，\n暮云秋影蘸潇湘。\n——蔡松年\n《鹧鸪天·赏荷》",
  "灵山多秀色，\n空水共氤氲。\n——张九龄\n《湖口望庐山瀑布泉》",
  "黄云万里动风色，\n白波九道流雪山。\n——李白\n《庐山谣寄卢侍御虚舟》",
  "雪消门外千山绿，\n 花发江边二月晴。\n——欧阳修\n《春日西湖寄谢法曹歌》",
  "遥望洞庭山水色，\n白银盘里一青螺。\n——刘禹锡\n《望洞庭》",
  "江上春山远，\n山下暮云长。\n——葛长庚\n《水调歌头》",
  "黄沙百战穿金甲，\n不破楼兰终不还。\n——王昌龄\n《从军行七首·其四》",
  "男儿何不带吴钩，\n收取关山五十州。\n——李贺\n《南园十三首·其五》",
  "苟利国家生死以，\n岂因祸福避趋之。\n——林则徐\n《赴戍登程口占示家人·其二》",
  "位卑未敢忘忧国，\n事定犹须待阖棺。\n——陆游\n《病起书怀》",
  "捐躯赴国难，\n视死忽如归！\n——曹植\n《白马篇》",
  "愿得此身长报国，\n何须生入玉门关。\n——戴叔伦\n《塞上曲二首·其二》",
  "只解沙场为国死，\n何须马革裹尸还。\n——徐锡麟\n《出塞》",
  "人生自古谁无死？\n留取丹心照汗青。\n——文天祥\n《过零丁洋》",
  "小来思报国，\n不是爱封侯。\n——岑参\n《送人赴安西》",
  "一身报国有万死，\n双鬓向人无再青。\n——陆游\n《夜泊水村》",
  "但使龙城飞将在，\n不教胡马度阴山。\n——王昌龄\n《出塞二首》",
  "醉卧沙场君莫笑，\n古来征战几人回？——王翰\n《凉州词二首·其一》",
  "早岁那知世事艰，\n中原北望气如山。\n——陆游\n《书愤五首·其一》",
  "一年三百六十日，\n多是横戈马上行。\n——戚继光\n《马上作》",
  "北斗七星高，\n哥舒夜带刀。\n——西鄙人\n《哥舒歌》",
  "明敕星驰封宝剑，\n辞君一夜取楼兰。\n——王昌龄\n《从军行七首》",
  "壮志饥餐胡虏肉，\n笑谈渴饮匈奴血。\n——岳飞\n《满江红·写怀》",
  "愿将腰下剑，\n直为斩楼兰。\n——李白\n《塞下曲六首》",
  "上马击狂胡，\n下马草军书。\n——陆游\n《观大散关图有感》",
  "百战沙场碎铁衣，\n城南已合数重围。\n——李白\n《从军行》",
  "数声风笛离亭晚，\n君向潇湘我向秦。\n——郑谷\n《淮上与友人别》",
  "无论去与住，\n俱是梦中人。\n——王勃\n《别薛华》",
  "日暮酒醒人已远，\n满天风雨下西楼。\n——许浑\n《谢亭送别》",
  "念去去，\n千里烟波，\n暮霭沉沉楚天阔。\n——柳永\n《雨霖铃》",
  "丈夫非无泪，\n不洒离别间。\n——陆龟蒙\n《别离》",
  "挥手自兹去，\n萧萧班马鸣。\n——李白\n《送友人》",
  "聚散匆匆，\n此恨年年有。\n——魏夫人\n《点绛唇》",
  "离多最是，\n东西流水，\n终解两相逢。\n——晏几道\n《少年游》",
  "猿啼客散暮江头，\n人自伤心水自流。\n——刘长卿\n《重送裴郎中贬吉州》",
  "一看肠一断，\n好去莫回头。\n——白居易\n《南浦别》",
  "劝君莫惜金缕衣，\n劝君惜取少年时。\n——杜秋娘\n《金缕衣》",
  "读书不觉已春深，\n一寸光阴一寸金。\n——王贞白\n《白鹿洞二首·其一》",
  "少年辛苦终身事，\n莫向光阴惰寸功。\n——杜荀鹤\n《题弟侄书堂》",
  "盛年不重来，\n一日难再晨。\n——陶渊明\n《杂诗·人生无根蒂》",
  "未觉池塘春草梦，\n阶前梧叶已秋声。\n——朱熹\n《偶成》",
  "青青园中葵，\n朝露待日晞。\n——佚名\n《长歌行》",
  "朝看水东流，\n暮看日西坠。\n——钱福\n《明日歌》",
  "晨昏滚滚水东流，\n今古悠悠日西坠。\n——钱福\n《明日歌》",
  "有歌有舞须早为，\n昨日健于今日时。\n——王建\n《短歌行》",
  "春宵一刻值千金，\n花有清香月有阴。\n——苏轼\n《春宵》",
  "稻花香里说丰年。\n听取蛙声一片。\n——辛弃疾\n《西江月·夜行黄沙道中》",
  "采菊东篱下，\n悠然见南山。\n——陶渊明\n《饮酒·其五》",
  "绿遍山原白满川，\n子规声里雨如烟。\n——翁卷\n《乡村四月》",
  "梅子金黄杏子肥，\n麦花雪白菜花稀。\n——范成大\n《四时田园杂兴·其二》",
  "乡村四月闲人少，\n才了蚕桑又插田。\n——翁卷\n《乡村四月》",
  "一畦春韭绿，\n十里稻花香。\n——曹雪芹\n《菱荇鹅儿水》",
  "水绕陂田竹绕篱，\n榆钱落尽槿花稀。\n——张舜民\n《村居》",
  "梅子青，\n梅子黄，\n菜肥麦熟养蚕忙。\n——祝允明\n《首夏山中行吟》",
  "布谷飞飞劝早耕，\n舂锄扑扑趁春晴。\n——姚鼐\n《山行》",
  "柴门寂寂黍饭馨，\n山家烟火春雨晴。\n——贯休\n《春晚书山家屋壁二首》",
  "柔情似水，\n佳期如梦，\n忍顾鹊桥归路！——秦观\n《鹊桥仙》",
  "况屈指中秋，\n十分好月，\n不照人圆。\n——辛弃疾\n《木兰花慢·滁州送范倅》",
  "五月五日午，\n赠我一枝艾。\n——文天祥\n《端午即事》",
  "佳节清明桃李笑，\n野田荒冢只生愁。\n——黄庭坚\n《清明》",
  "佳节又重阳，\n玉枕纱厨，\n半夜凉初透。\n——李清照\n《醉花阴》",
  "听元宵，\n今岁嗟呀，\n愁也千家，\n怨也千家。\n——王磐\n《古蟾宫·元宵》",
  "元宵佳节，\n融和天气，\n次第岂无风雨。\n——李清照\n《永遇乐》",
  "碧艾香蒲处处忙。\n谁家儿共女，\n庆端阳。\n——舒頔\n《小重山·端午》",
  "今宵是除夕，\n明日又新年。\n——于谦\n《除夕》",
  "蜡鹅花下烛如银。\n钗符金胜，\n又见一家春。\n——李慈铭\n《临江仙·癸未除夕作》",
  "微雨众卉新，\n一雷惊蛰始。\n——韦应物\n《观田家》",
  "春分雨脚落声微，\n柳岸斜风带客归。\n——徐铉\n《七绝·苏醒》",
  "清明时节雨纷纷，\n路上行人欲断魂。\n——杜牧\n《清明》",
  "芒种初过雨及时，\n纱厨睡起角巾攲。\n——陆游\n《芒种后经旬无日不雨偶得长句》",
  "且欣小暑能如此，\n更愿新秋得似今。\n——韩淲\n《十八日小暑大雨》",
  "霜降碧天静，\n秋事促西风。\n——叶梦得\n《水调歌头·九月望日与客习射西园余偶病不能射》",
  "白露团甘子，\n清晨散马蹄。\n——杜甫\n《白露》",
  "金气秋分，\n风清露冷秋期半。\n——谢逸\n《点绛唇》",
  "袅袅凉风动，\n凄凄寒露零。\n——白居易\n《池上》",
  "时候频过小雪天，\n江南寒色未曾偏。\n——陆龟蒙\n《小雪后书事》",
  "春风如贵客，\n一到便繁华。\n——袁枚\n《春风》",
  "竹外桃花三两枝，\n春江水暖鸭先知。\n——苏轼\n《惠崇春江晚景》",
  "天街小雨润如酥，\n草色遥看近却无。\n——韩愈\n《早春呈水部张十八员外》",
  "迟日江山丽，\n春风花草香。\n——杜甫\n《绝句二首》",
  "绿杨烟外晓寒轻，\n红杏枝头春意闹。\n——宋祁\n《玉楼春·春景》",
  "草长莺飞二月天，\n拂堤杨柳醉春烟。\n——高鼎\n《村居》",
  "春路雨添花，\n花动一山春色。\n——秦观\n《好事近·梦中作》",
  "春色满园关不住，\n一枝红杏出墙来。\n——叶绍翁\n《游园不值》",
  "燕子不归春事晚，\n一汀烟雨杏花寒。\n——戴叔伦\n《苏溪亭》",
  "花气袭人知骤暖，\n鹊声穿树喜新晴。\n——陆游\n《村居书喜》",
  "小荷才露尖尖角，\n早有蜻蜓立上头。\n——杨万里\n《小池》",
  "接天莲叶无穷碧，\n映日荷花别样红。\n——杨万里\n《晓出净慈寺送林子方》",
  "水晶帘动微风起，\n满架蔷薇一院香。\n——高骈\n《山亭夏日》",
  "漠漠水田飞白鹭，\n阴阴夏木啭黄鹂。\n——王维\n《积雨辋川庄作》",
  "叶上初阳干宿雨，\n水面清圆，\n一一风荷举。\n——周邦彦\n《苏幕遮·燎沉香》",
  "昼出耘田夜绩麻，\n村庄儿女各当家。\n——范成大\n《夏日田园杂兴·其七》",
  "微雨过，\n小荷翻。\n榴花开欲然。\n——苏轼\n《阮郎归·初夏》",
  "树阴满地日当午，\n梦觉流莺时一声。\n——苏舜钦\n《夏意》",
  "风蒲猎猎小池塘，\n过雨荷花满院香，\n沉李浮瓜冰雪凉。\n——李重元\n《忆王孙·夏词》",
  "东园载酒西园醉，\n摘尽枇杷一树金。\n——戴敏\n《初夏游张园》",
  "自古逢秋悲寂寥，\n我言秋日胜春朝。\n——刘禹锡\n《秋词》",
  "秋阴不散霜飞晚，\n留得枯荷听雨声。\n——李商隐\n《宿骆氏亭寄怀崔雍崔衮》",
  "秋风生渭水，\n落叶满长安。\n——贾岛\n《忆江上吴处士》",
  "树树皆秋色，\n山山唯落晖。\n——王绩\n《野望》",
  "秋风萧瑟天气凉，\n草木摇落露为霜，\n群燕辞归鹄南翔。\n——曹丕\n《燕歌行二首·其一》",
  "金风细细。\n叶叶梧桐坠。\n——晏殊\n《清平乐·金风细细》",
  "丹枫万叶碧云边，\n黄花千点幽岩下。\n——张抡\n《踏莎行·秋入云山》",
  "况属高风晚，\n山山黄叶飞。\n——王勃\n《山中》",
  "一点残红欲尽时。\n乍凉秋气满屏帏。\n——周紫芝\n《鹧鸪天》",
  "孤村落日残霞，\n轻烟老树寒鸦，\n一点飞鸿影下。\n——白朴\n《天净沙·秋》",
  "十月江南天气好，\n可怜冬景似春华。\n——白居易\n《早冬》",
  "冬夜夜寒觉夜长，\n沉吟久坐坐北堂。\n——李白\n《夜坐吟》",
  "晚来天欲雪，\n能饮一杯无。\n——白居易\n《问刘十九》",
  "日暮苍山远，\n天寒白屋贫。\n——刘长卿\n《逢雪宿芙蓉山主人》",
  "晨起开门雪满山，\n雪晴云淡日光寒。\n——郑燮\n《山中雪后》",
  "江南江北雪漫漫，\n遥知易水寒。\n——向子諲\n《阮郎归·绍兴乙卯大雪行鄱阳道中》",
  "同为懒慢园林客，\n共对萧条雨雪天。\n——白居易\n《雪夜小饮赠梦得》",
  "浮生只合尊前老，\n雪满长安道。\n——舒亶\n《虞美人·寄公度》",
  "邯郸驿里逢冬至，\n抱膝灯前影伴身。\n——白居易\n《邯郸冬至夜思家》",
  "雪中何以赠君别，\n惟有青青松树枝。\n——岑参\n《天山雪歌送萧治归京》",
  "疏影横斜水清浅，\n暗香浮动月黄昏。\n《山园小梅》\n—— 宋 林逋",
  "西塞山前白鹭飞，\n桃花流水鳜鱼肥。\n《渔歌子》\n——唐 张志和",
  "人生不相见，\n动如参与商。\n《赠卫八处士》\n——唐 杜甫",
  "桃之夭夭，\n灼灼其华。\n《诗经·桃夭》",
  "人面不知何处去，\n桃花依旧笑春风。\n《题都城南庄》\n——唐 崔护",
  "人间四月芳菲尽，\n山寺桃花始盛开。\n《大林寺桃花》\n——唐 白居易",
  "沾衣欲湿杏花雨，\n吹面不寒杨柳风。\n《绝句（古木阴中系短篷）》\n——宋 志南和尚",
  "春色满园关不住，\n一枝红杏出墙来。\n《游园不值》\n——宋 叶绍翁",
  "绿杨烟外晓寒轻，\n红杏枝头春意闹。\n《玉楼春·春景》\n——宋 宋祁",
  "只恐夜深花睡去，\n故烧高烛照红妆。\n《海棠》\n——宋 苏轼",
  "百亩庭中半是苔，\n桃花净尽菜花开。\n《再游玄都观》\n——唐 刘禹锡",
  "儿童急走追黄蝶，\n飞入菜花无处寻。\n《宿新市徐公店》\n——宋 杨万里",
  "日长篱落无人过，\n唯有蜻蜓蛱蝶飞。\n《四时田园杂兴》\n——宋 范成大",
  "身无彩凤双飞翼，\n心有灵犀一点通。\n《无题》\n——唐 李商隐",
  "春江潮水连海平，\n海上明月共潮生。\n《春江花月夜》\n——唐  张若虚",
  "细雨鱼儿出，\n微风燕子斜。\n《水槛遣心》\n——唐 杜甫",
  "无可奈何花落去，\n似曾相识燕归来。\n《浣溪沙》\n——宋   晏殊",
  "流光容易把人抛，\n红了樱桃，\n绿了芭蕉。\n《一剪梅·舟过吴江》\n——南宋 蒋捷",
  "彩线轻缠红玉臂，\n小符斜挂绿云鬟。家人相见一千年。\n《浣溪沙·端午》\n——宋 苏轼",
  "黄梅时节家家雨，\n青草池塘处处蛙。\n《约客》\n——宋 赵师秀",
  "意欲捕鸣蝉，\n忽然闭口立。\n《所见》\n——清 袁枚",
  "小荷才楼尖尖角，\n早有蜻蜓立上头。\n《小池》\n——宋 杨万里",
  "荷叶罗裙一色裁，\n芙蓉向脸两边开。\n《采莲曲》\n——唐 王昌龄",
  "涉江采芙蓉，\n蓝泽多芳草。\n《古诗十九首·涉江采芙蓉》\n——汉",
  "接天莲叶无穷碧，\n映日荷花别样红。\n《晓出净慈寺送林子方》\n——宋 杨万里",
  "最喜小儿无赖，\n溪头卧剥莲蓬。\n《清平乐·村居》\n——宋 辛弃疾",
  "银烛秋光冷画屏，\n轻罗小扇扑流萤。\n《秋夕》\n——唐 杜牧",
  "两情若是久长时，\n又岂在朝朝暮暮。\n《鹊桥仙》\n——宋 秦观",
  "月落乌啼霜满天，\n江枫渔火对愁眠。\n《枫桥夜泊》\n——唐 张继",
  "远上寒山石径斜，\n白云生处有人家。\n《山行》\n——唐 杜牧",
  "自古逢秋悲寂寥，\n我言秋日胜春朝。\n《秋词》\n——唐 刘禹锡",
  "落霞与孤鹜齐飞，\n秋水共长天一色。\n《滕王阁序》\n——唐 王勃",
  "星垂平野阔，\n月涌大江流。\n《旅夜书怀》\n——唐 杜甫",
  "但愿人长久，\n千里共婵娟。\n《水调歌头》\n——宋 苏轼",
  "绿树村边合，\n青山郭外斜。\n《过故人庄》\n——唐 孟浩然",
  "莫道不消魂，\n帘卷西风，\n人比黄花瘦。\n《醉花阴·九日》\n——宋 李清照",
  "采菊东篱下，\n悠然见南山。\n《饮酒·其五》\n——晋 陶渊明",
  "明月松间照，\n清泉石上流。\n《山居秋暝》\n——唐 王维 ",
  "一年好景君须记，\n最是橙黄橘绿时。\n《赠刘景文／冬景》\n——宋 苏轼",
  "千山鸟飞绝，\n万径人踪灭。\n《江雪》\n——唐 柳宗元",
  "草枯鹰眼疾，\n雪尽马蹄轻。\n《观猎》\n——唐 王维",
  "了却君王天下事，\n赢得生前身后名。\n《破阵子》\n——宋 辛弃疾",
  "夜深知雪重，\n时闻折竹声。\n《夜雪》\n——唐 白居易",
  "千门万户曈曈日，\n总把新桃换旧符。\n《元日》\n——宋 王安石",
  "火树银花合，\n星桥铁锁开。\n《正月十五夜》\n——唐 苏味道",
  "蓦然回首，\n那人却在灯火阑珊处。\n《青玉案·元夕》\n——宋 辛弃疾",
  "『不知魂已断，空有梦相随。除却天边月，没人知。』\n《女冠子·四月十七》\n	——韦庄"
}

-- 获取随机诗句
local function get_random_chicken_soup()
  math.randomseed(os.time())
  local index = math.random(1, #chicken_soups)
  return chicken_soups[index]
end

-- 安全的字符长度计算函数
local function get_text_length(text)
  if not text or text == "" then
    return 0
  end

  -- 优先使用 utf8.len
  if utf8 and utf8.len then
    local utf8_len = utf8.len(text)
    if utf8_len then
      return utf8_len
    end
  end

  -- 回退方案：手动计算UTF-8字符
  local count = 0
  local i = 1
  while i <= #text do
    local byte = text:byte(i)
    if byte < 128 then
      -- ASCII字符
      count = count + 1
      i = i + 1
    elseif byte >= 192 and byte < 224 then
      -- 2字节UTF-8
      count = count + 1
      i = i + 2
    elseif byte >= 224 and byte < 240 then
      -- 3字节UTF-8
      count = count + 1
      i = i + 3
    elseif byte >= 240 then
      -- 4字节UTF-8
      count = count + 1
      i = i + 4
    else
      -- 无效字节，跳过
      i = i + 1
    end
  end
  return count
end

-- 时间戳工具函数
local function start_of_day(t)
  if not t or not t.year or not t.month or not t.day then
    return 0
  end
  return os.time { year = t.year, month = t.month, day = t.day, hour = 0 }
end

local function start_of_week(t)
  if not t or not t.year or not t.month or not t.day or not t.wday then
    return 0
  end
  local d = t.wday == 1 and 6 or (t.wday - 2)
  return os.time { year = t.year, month = t.month, day = t.day - d, hour = 0 }
end

local function start_of_month(t)
  if not t or not t.year or not t.month then
    return 0
  end
  return os.time { year = t.year, month = t.month, day = 1, hour = 0 }
end

local function start_of_year(t)
  if not t or not t.year then
    return 0
  end
  return os.time { year = t.year, month = 1, day = 1, hour = 0 }
end

-- 判断是否是统计命令
local function is_summary_command(text)
  return text == "tjrt" or text == "tjzt" or text == "tjyt" or text == "tjnt" or text == "tjqk"
end

-- 获取方案显示名称（优先中文名）
local function get_schema_display_name(env)
  if not env or not env.engine or not env.engine.schema then
    return "未知方案"
  end

  local schema = env.engine.schema
  local config = schema.config

  -- 优先尝试获取中文名称
  if config then
    local name = config:get_string("schema/name")
    if name and name ~= "" then
      return name
    end
  end

  -- 回退到schema_id
  return schema.schema_id or "未知方案"
end

-- 更新统计数据
local function update_stats(input_length, env)
  local now = os.date("*t")
  local now_ts = os.time(now)

  local day_ts = start_of_day(now)
  local week_ts = start_of_week(now)
  local month_ts = start_of_month(now)
  local year_ts = start_of_year(now)

  -- 确保所有统计对象都存在
  input_stats.daily = input_stats.daily or { count = 0, length = 0, fastest = 0, ts = 0 }
  input_stats.weekly = input_stats.weekly or { count = 0, length = 0, fastest = 0, ts = 0 }
  input_stats.monthly = input_stats.monthly or { count = 0, length = 0, fastest = 0, ts = 0 }
  input_stats.yearly = input_stats.yearly or { count = 0, length = 0, fastest = 0, ts = 0 }
  input_stats.yesterday = input_stats.yesterday or { count = 0, length = 0, fastest = 0, ts = 0 }
  input_stats.lengths = input_stats.lengths or {}
  input_stats.recent = input_stats.recent or {}

  -- 检查是否是新的一天，如果是则保存昨日数据
  if input_stats.daily.ts ~= 0 and input_stats.daily.ts ~= day_ts then
    input_stats.yesterday = {
      count = input_stats.daily.count,
      length = input_stats.daily.length,
      fastest = input_stats.daily.fastest,
      ts = input_stats.daily.ts
    }
  end

  if input_stats.daily.ts ~= day_ts then
    input_stats.daily = { count = 0, length = 0, fastest = 0, ts = day_ts }
    input_stats.daily_max = 0
    input_stats.recent = {}
  end
  if input_stats.weekly.ts ~= week_ts then
    input_stats.weekly = { count = 0, length = 0, fastest = 0, ts = week_ts }
  end
  if input_stats.monthly.ts ~= month_ts then
    input_stats.monthly = { count = 0, length = 0, fastest = 0, ts = month_ts }
  end
  if input_stats.yearly.ts ~= year_ts then
    input_stats.yearly = { count = 0, length = 0, fastest = 0, ts = year_ts }
  end

  -- 更新记录
  local update = function(stat)
    if stat then
      stat.count = (stat.count or 0) + 1
      stat.length = (stat.length or 0) + input_length
    end
  end
  update(input_stats.daily)
  update(input_stats.weekly)
  update(input_stats.monthly)
  update(input_stats.yearly)

  if input_length > (input_stats.daily_max or 0) then
    input_stats.daily_max = input_length
  end

  input_stats.lengths[input_length] = (input_stats.lengths[input_length] or 0) + 1

  -- 最近一分钟统计（修复版）
  local ts = os.time()
  table.insert(input_stats.recent, { ts = ts, len = input_length })

  -- 清理超过1分钟的数据并计算当前分钟的速度
  local threshold = ts - 60
  local current_minute_total = 0
  local new_recent = {}

  for _, item in ipairs(input_stats.recent) do
    if item and item.ts and item.ts >= threshold then
      current_minute_total = current_minute_total + (item.len or 0)
      table.insert(new_recent, item)
    end
  end
  input_stats.recent = new_recent

  -- 只更新当前时间段的最快速度
  if current_minute_total > (input_stats.daily.fastest or 0) then
    input_stats.daily.fastest = current_minute_total
  end

  -- 周、月、年的最快速度应该是各自时间段内 daily.fastest 的最大值
  if current_minute_total > (input_stats.weekly.fastest or 0) then
    input_stats.weekly.fastest = current_minute_total
  end
  if current_minute_total > (input_stats.monthly.fastest or 0) then
    input_stats.monthly.fastest = current_minute_total
  end
  if current_minute_total > (input_stats.yearly.fastest or 0) then
    input_stats.yearly.fastest = current_minute_total
  end
end

-- 表序列化工具
local function serialize_table(tbl, indent)
  indent = indent or 0
  local spaces = string.rep(" ", indent)
  local lines = { "{" }

  for k, v in pairs(tbl) do
    local key = (type(k) == "string") and ("[\"" .. k .. "\"]") or ("[" .. k .. "]")
    local val

    if type(v) == "table" then
      val = serialize_table(v, indent + 4)
    elseif type(v) == "string" then
      val = '"' .. v .. '"'
    else
      val = tostring(v)
    end
    table.insert(lines, string.format("%s    %s = %s,", spaces, key, val))
  end
  table.insert(lines, spaces .. "}")
  return table.concat(lines, "\n")
end

-- 保存至文件
local function save_stats()
  local path = (rime_api and rime_api.get_user_data_dir and rime_api:get_user_data_dir() or "") ..
      "/lua/data/input_stats/data.lua"
  local file = io.open(path, "w")
  if not file then
    return false
  end
  file:write("return " .. serialize_table(input_stats) .. "\n")
  file:close()
  return true
end

-- 显示函数（日统计）- 增加昨日对比
local function format_daily_summary(schema_name)
  local s = input_stats.daily or { count = 0, length = 0, fastest = 0 }
  local y = input_stats.yesterday or { count = 0, length = 0, fastest = 0 }

  if s.count == 0 then
    return "※ 今天没有任何记录。\n\n" .. (get_random_chicken_soup() or "❤ 今日无记录，明日再战！")
  end

  -- 计算与昨日的对比
  local comparison_text = ""
  if y and y.length > 0 then
    local diff = s.length - y.length
    local diff_percent = 0
    if y.length > 0 then
      diff_percent = (diff / y.length) * 100
    end

    if diff > 0 then
      comparison_text = string.format("比昨日多%d字 (+%.1f%%)", diff, diff_percent)
    elseif diff < 0 then
      comparison_text = string.format("比昨日少%d字 (%.1f%%)", -diff, diff_percent)
    else
      comparison_text = "与昨日持平"
    end
  else
    comparison_text = "昨日无记录"
  end

  return string.format(
    "※ 今天的统计：\n%s\n◉ 今天\n共上屏[%d]次\n共输入[%d]字\n%s\n最快一分钟输入了[%d]字\n%s\n%s\n%s\n◉ 方案：%s\n%s",
    string.rep("─", 12), s.count, s.length, comparison_text, s.fastest or 0,
    string.rep("─", 12), get_random_chicken_soup() or "❤ 继续努力！",
    string.rep("─", 12), schema_name, string.rep("─", 12))
end

-- 显示函数（周统计）
local function format_weekly_summary(schema_name)
  local s = input_stats.weekly or { count = 0, length = 0, fastest = 0 }
  if s.count == 0 then
    return "※ 本周没有任何记录。\n\n" .. (get_random_chicken_soup() or "❤ 本周无记录，加油！")
  end

  return string.format(
    "※ 本周的统计：\n%s\n◉ 本周共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n周内单日最多一次输入[%d]字\n%s\n%s\n%s\n◉ 方案：%s\n%s",
    string.rep("─", 12), s.count, s.length, s.fastest or 0, input_stats.daily_max or 0,
    string.rep("─", 12), get_random_chicken_soup() or "❤ 继续努力！",
    string.rep("─", 12), schema_name, string.rep("─", 12))
end

-- 显示函数（月统计）
local function format_monthly_summary(schema_name)
  local s = input_stats.monthly or { count = 0, length = 0, fastest = 0 }
  if s.count == 0 then
    return "※ 本月没有任何记录。\n\n" .. (get_random_chicken_soup() or "❤ 本月无记录，继续加油！")
  end

  return string.format(
    "※ 本月的统计：\n%s\n◉ 本月共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n%s\n%s\n%s\n◉ 方案：%s\n%s",
    string.rep("─", 12), s.count, s.length, s.fastest or 0,
    string.rep("─", 12), get_random_chicken_soup() or "❤ 继续努力！",
    string.rep("─", 12), schema_name, string.rep("─", 12))
end

-- 显示函数（年统计）
local function format_yearly_summary(schema_name)
  local s = input_stats.yearly or { count = 0, length = 0, fastest = 0 }
  if s.count == 0 then
    return "※ 本年没有任何记录。\n\n" .. (get_random_chicken_soup() or "❤ 本年无记录，新年新气象！")
  end

  local fav = 0
  if input_stats.lengths then
    local length_counts = {}
    for length, count in pairs(input_stats.lengths) do
      if type(length) == "number" and type(count) == "number" then
        table.insert(length_counts, { length = length, count = count })
      end
    end
    table.sort(length_counts, function(a, b) return a.count > b.count end)
    fav = length_counts[1] and length_counts[1].length or 0
  end

  return string.format(
    "※ 本年的统计：\n%s\n◉ 本年共上屏[%d]次\n共输入[%d]字\n最快一分钟输入了[%d]字\n您最常输入长度为[%d]的词组\n%s\n%s\n%s\n◉ 方案：%s\n%s",
    string.rep("─", 12), s.count, s.length, s.fastest or 0, fav,
    string.rep("─", 12), get_random_chicken_soup() or "❤ 继续努力！",
    string.rep("─", 12), schema_name, string.rep("─", 12))
end

-- 转换器函数：处理统计命令
local function translator(input, seg, env)
  local summary = ""

  -- 动态获取方案信息
  local schema_name = get_schema_display_name(env)

  if input == "tjrt" then
    summary = format_daily_summary(schema_name)
  elseif input == "tjzt" then
    summary = format_weekly_summary(schema_name)
  elseif input == "tjyt" then
    summary = format_monthly_summary(schema_name)
  elseif input == "tjnt" then
    summary = format_yearly_summary(schema_name)
  elseif input == "tjqk" then
    -- 清空数据但保留昨日数据
    local yesterday_data = input_stats.yesterday or { count = 0, length = 0, fastest = 0, ts = 0 }
    input_stats = {
      daily = { count = 0, length = 0, fastest = 0, ts = 0 },
      weekly = { count = 0, length = 0, fastest = 0, ts = 0 },
      monthly = { count = 0, length = 0, fastest = 0, ts = 0 },
      yearly = { count = 0, length = 0, fastest = 0, ts = 0 },
      lengths = {},
      daily_max = 0,
      recent = {},
      yesterday = yesterday_data -- 保留昨日数据
    }
    save_stats()
    summary = "※ 所有统计数据已清空（昨日数据保留）。"
  end

  if summary ~= "" then
    cand = Candidate("stat", seg.start, seg._end, summary, "〈统计输入信息〉")
    cand.quality = 999
    yield(cand)
  end
end

-- 加载保存的统计数据（data.lua）
local function load_stats_from_lua_file()
  local path = (rime_api and rime_api.get_user_data_dir and rime_api:get_user_data_dir() or "") ..
      "/lua/data/input_stats/data.lua"
  local ok, result = pcall(function()
    local f = loadfile(path)
    if f then
      return f()
    end
    return nil
  end)

  if ok and type(result) == "table" then
    -- 合并保存的数据，确保所有必要字段都存在
    for k, v in pairs(result) do
      input_stats[k] = v
    end

    -- 确保所有必要字段都存在
    input_stats.daily = input_stats.daily or { count = 0, length = 0, fastest = 0, ts = 0 }
    input_stats.weekly = input_stats.weekly or { count = 0, length = 0, fastest = 0, ts = 0 }
    input_stats.monthly = input_stats.monthly or { count = 0, length = 0, fastest = 0, ts = 0 }
    input_stats.yearly = input_stats.yearly or { count = 0, length = 0, fastest = 0, ts = 0 }
    input_stats.lengths = input_stats.lengths or {}
    input_stats.recent = input_stats.recent or {}
    input_stats.yesterday = input_stats.yesterday or { count = 0, length = 0, fastest = 0, ts = 0 }
    input_stats.daily_max = input_stats.daily_max or 0
  else
    -- 保底初始化，防止错误
    input_stats = {
      daily = { count = 0, length = 0, fastest = 0, ts = 0 },
      weekly = { count = 0, length = 0, fastest = 0, ts = 0 },
      monthly = { count = 0, length = 0, fastest = 0, ts = 0 },
      yearly = { count = 0, length = 0, fastest = 0, ts = 0 },
      lengths = {},
      daily_max = 0,
      recent = {},
      yesterday = { count = 0, length = 0, fastest = 0, ts = 0 }
    }
  end
end

local function init(env)
  if not env or not env.engine then
    return
  end

  local ctx = env.engine.context

  -- 加载历史统计数据
  load_stats_from_lua_file()

  -- 注册提交通知回调
  if ctx and ctx.commit_notifier then
    ctx.commit_notifier:connect(function(ctx)
      if not ctx then return end

      local commit_text = ctx:get_commit_text()
      if not commit_text or commit_text == "" then return end

      -- 排除统计命令
      if is_summary_command(commit_text) then return end

      -- 排除统计候选上屏内容
      if commit_text:match("^[※◉]") then return end

      -- 使用安全的字符长度计算
      local input_length = get_text_length(commit_text)

      update_stats(input_length, env)
      save_stats()
    end)
  end
end

return { init = init, func = translator }
