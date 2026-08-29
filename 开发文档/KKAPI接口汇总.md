# KKAPI 接口汇总

- 来源站点：[KKAPI开发者文档](https://create.kkdzpt.com/kkapidoc/#/)
- 生成日期：2026-06-18
- 收录范围：`KKAPI (kkapi)` 与 `KK-JAPI (kkjapi)` 的接口文档、分类说明与错误码页面
- 说明：本文档为本地整理版，保留参数、返回值、示例与错误码，文内原始相对链接已转换为绝对链接

---

## 服务器存档

> 魔兽争霸III多人联机的原有机制中，所有数据仅限当局游戏内使用，游戏局一旦结束所有数据即失效。
>
> 服务器存档技术允许开发者将每名玩家在游戏局内的一部分关键信息保存至平台服务器，以实现玩家数据在多局游戏中进行共享，该数据以Key/Value的形式存储。

原文：[menu_kkapi_storage.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_storage.md)

---

### 服务器存档错误码列表

> 错误码持续更新中，如有问题请反馈给我们



| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1759 | 数据类型不正确                     |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1941 | 服务器存档写入频率异常 |
| 1250 | 增加的值超出上限（服务器存档防刷） |
| 1266 | 增加的值超出上限（服务器存档防刷） |
| 1267 | 防刷分时间点限制 不在范围时间内（每天几点~几点） |
| 1268 | 组防刷分数据异常 |
| 1270 | 防刷分出现数据异常 |
| 1272 | 防刷分 当局 差值达到上限|
| 1273 | 防刷分 当局 累计值达到上限|
| 1274 | 防刷分 每日 达到上限|
| 10322| 存档列表中没有这个KEY（绑定了作者之家存档列表，只能存储列表范围内的KEY）|
| 1106 | 游戏内没有这个玩家|

原文：[kkapi/Error_Server.md](https://create.kkdzpt.com/kkapidoc/kkapi/Error_Server.md)

---

### 保存服务器存档

将变量存储到服务器。

数据保存时会受到开发者平台配置的写入规则限制（防刷分、只增等）。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 存档变量Key，最大长度63位 |
| value       | string \| 字符串 | 存档变量Value，最大长度63位  |

##### 返回值
无

##### 调用示例

**WorldEdit Trigger**

*不支持，请使用[保存字符串变量至服务器](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_StoreString)替代*

**JASS**

```JASS
native DzAPI_Map_SaveServerValue takes player whichPlayer, string key, string value returns boolean

call DzAPI_Map_SaveServerValue( Player(0), "variablename", "value" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzAPI_Map_SaveServerValue( jass.Player(0), "itemkey", "value" ) 
```

##### 错误代码

| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1759 | 数据类型不正确                     |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1941 | 服务器存档写入频率异常 |
| 1250 | 增加的值超出上限（服务器存档防刷） |
| 1266 | 增加的值超出上限（服务器存档防刷） |
| 1267 | 防刷分时间点限制 不在范围时间内（每天几点~几点） |
| 1268 | 组防刷分数据异常 |
| 1270 | 防刷分出现数据异常 |
| 1272 | 防刷分 当局 差值达到上限|
| 1273 | 防刷分 当局 累计值达到上限|
| 1274 | 防刷分 每日 达到上限|
| 10322| 存档列表中没有这个KEY（绑定了作者之家存档列表，只能存储列表范围内的KEY）|
| 1106 | 游戏内没有这个玩家|

原文：[kkapi/DzAPI_Map_SaveServerValue.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SaveServerValue.md)

---

### 读取服务器存档

从服务器上读取变量数据

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 存档变量Key，最大长度63位 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 服务器上最新的存档变量Value |

##### 调用示例

**WorldEdit Trigger**

*不支持，请使用[读取服务器上的字符串变量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetStoredString)替代*

**JASS**

```JASS
native DzAPI_Map_GetServerValue takes player whichPlayer, string key returns string

call DzAPI_Map_GetServerValue( Player(0), "variablename" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzAPI_Map_GetServerValue( jass.Player(0), "variablename" ) 
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1190 | 存档初始化加载失败 |

原文：[kkapi/DzAPI_Map_GetServerValue.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerValue.md)

---

### 保存字符串变量至服务器

将字符串类型的变量数据存储到服务器。 

数据保存时会受到开发者平台配置的写入规则限制（防刷分、只增等）。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 存档变量Key，最大长度63位；<br />保存至服务器时会在存档变量Key上增加前缀 “S” |
| value       | string \| 字符串 | 存档变量Value，最大长度63位  |

##### 返回值
无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_StoreString](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_StoreString.png)

**JASS**

```JASS
native DzAPI_Map_SaveServerValue takes player whichPlayer, string key, string value returns boolean

function DzAPI_Map_StoreString takes player whichPlayer, string key, string value returns nothing
	set key = "S" + key
	call DzAPI_Map_SaveServerValue( whichPlayer, key, value )
	set key = null
	set whichPlayer = null
endfunction
	
call DzAPI_Map_StoreString( Player(0), "variablename", "value" )
```

**LUA**

<font color=gray>请使用 [保存服务器存档](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SaveServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1759 | 数据类型不正确                     |
| 1766 | 只增存档不能被减少                 |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1941 | 服务器存档写入频率异常 |
| 1250 | 增加的值超出上限（服务器存档防刷） |

原文：[kkapi/DzAPI_Map_StoreString.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_StoreString.md)

---

### 保存整数变量至服务器

将整数类型的变量数据存储到服务器。 

数据保存时会受到开发者平台配置的写入规则限制（防刷分、只增等）。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 存档变量Key，最大长度63位；<br />保存至服务器时会在存档变量Key上增加前缀 “I” |
| value       | integer \| 整数 | 存档变量Value  |

##### 返回值
无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_StoreInteger](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_StoreInteger.png)

**JASS**

```JASS
native DzAPI_Map_SaveServerValue takes player whichPlayer, string key, string value returns boolean

function DzAPI_Map_StoreInteger takes player whichPlayer, string key, integer value returns nothing
	set key = "I" + key
	call DzAPI_Map_SaveServerValue( whichPlayer, key, I2S( value ) )
	set key = null
	set whichPlayer = null
endfunction
	
call DzAPI_Map_StoreInterger( Player(0), "variablename", true )
```

**LUA**

<font color=gray>请使用 [保存服务器存档](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SaveServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1759 | 数据类型不正确                     |
| 1766 | 只增存档不能被减少                 |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1941 | 服务器存档写入频率异常 |
| 1250 | 增加的值超出上限（服务器存档防刷） |

原文：[kkapi/DzAPI_Map_StoreInteger.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_StoreInteger.md)

---

### 保存实数变量至服务器

将实数类型的变量数据存储到服务器。 

数据保存时会受到开发者平台配置的写入规则限制（防刷分、只增等）。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 存档变量Key，最大长度63位；<br />保存至服务器时会在存档变量Key上增加前缀 “R” |
| value       | real \| 实数 | 存档变量Value  |

##### 返回值
无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_StoreReal](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_StoreReal.png)

**JASS**

```JASS
native DzAPI_Map_SaveServerValue takes player whichPlayer, string key, string value returns boolean

function DzAPI_Map_StoreReal takes player whichPlayer, string key, real value returns nothing
	set key = "R" + key
	call DzAPI_Map_SaveServerValue( whichPlayer, key, R2S( value ) )
	set key = null
	set whichPlayer = null
endfunction
	
call DzAPI_Map_StoreReal( Player(0), "variablename", true )
```

**LUA**

<font color=gray>请使用 [保存服务器存档](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SaveServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1759 | 数据类型不正确                     |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1941 | 服务器存档写入频率异常 |
| 1250 | 增加的值超出上限（服务器存档防刷） |

原文：[kkapi/DzAPI_Map_StoreReal.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_StoreReal.md)

---

### 保存布尔值变量至服务器

将布尔类型的变量数据存储到服务器。 

数据保存时会受到开发者平台配置的写入规则限制（防刷分、只增等）。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 存档变量Key，最大长度63位；<br />保存至服务器时会在存档变量Key上增加前缀 “B” |
| value       | boolean \| 布尔值 | 存档变量Value  |

##### 返回值
无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_StoreBoolean](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_StoreBoolean.png)

**JASS**

```JASS
native DzAPI_Map_SaveServerValue takes player whichPlayer, string key, string value returns boolean

function DzAPI_Map_StoreBoolean takes player whichPlayer, string key, boolean value returns nothing
	set key = "B" + key
	if( value ) then
		call DzAPI_Map_SaveServerValue( whichPlayer, key, "1" )
	else
		call DzAPI_Map_SaveServerValue( whichPlayer, key, "0" )
	endif
	set key = null
	set whichPlayer = null
endfunction
	
call DzAPI_Map_StoreBoolean( Player(0), "variablename", true )
```

**LUA**

<font color=gray>请使用 [保存服务器存档](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SaveServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1759 | 数据类型不正确                     |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1941 | 服务器存档写入频率异常 |
| 1250 | 增加的值超出上限（服务器存档防刷） |

原文：[kkapi/DzAPI_Map_StoreBoolean.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_StoreBoolean.md)

---

### 读取服务器上的字符串变量

从服务器上获取字符串类型的变量数据 

##### 参数
| 参数名      | 类型             | 说明                                                         |
| :---------- | :--------------- | :----------------------------------------------------------- |
| whichPlayer | player \| 玩家   | 玩家                                                         |
| key         | string \| 字符串 | 存档变量Key，最大长度63位<br />实际读取时会在存档变量Key上增加前缀 “S” |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 服务器上的存档变量Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetStoredString](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetStoredString.png)

**JASS** 

```JASS
native DzAPI_Map_GetServerValue takes player whichPlayer, string key returns string

function DzAPI_Map_GetStoredString takes player whichPlayer, string key returns string
	return DzAPI_Map_GetServerValue( whichPlayer, "S" + key )
endfunction
	
call DzAPI_Map_GetStoredString( Player(0), "variablename" )
```

**LUA**

<font color=gray>请使用 [读取服务器变量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1190 | 存档初始化加载失败 |

原文：[kkapi/DzAPI_Map_GetStoredString.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetStoredString.md)

---

### 读取服务器上的整数变量

从服务器上获取整数类型的变量数据 

##### 参数
| 参数名      | 类型             | 说明                                                         |
| :---------- | :--------------- | :----------------------------------------------------------- |
| whichPlayer | player \| 玩家   | 玩家                                                         |
| key         | string \| 字符串 | 存档变量Key，最大长度63位<br />实际读取时会在存档变量Key上增加前缀 “I” |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 服务器上的存档变量Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetStoredInteger](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetStoredInteger.png)

**JASS** 
```JASS
native DzAPI_Map_GetServerValue takes player whichPlayer, string key returns string

function DzAPI_Map_GetStoredInteger takes player whichPlayer, string key returns integer
	local integer value
	set key = "I" + key
	set value = S2I( DzAPI_Map_GetServerValue( whichPlayer, key ) )
	set key = null
	set whichPlayer = null
	return value
endfunction
	
call DzAPI_Map_GetStoredInteger( Player(0), "variablename" )
```

**LUA**

<font color=gray>请使用 [读取服务器变量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1190 | 存档初始化加载失败 |

原文：[kkapi/DzAPI_Map_GetStoredInteger.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetStoredInteger.md)

---

### 读取服务器上的实数变量

从服务器上获取实数类型的变量数据 

##### 参数
| 参数名      | 类型             | 说明                                                         |
| :---------- | :--------------- | :----------------------------------------------------------- |
| whichPlayer | player \| 玩家   | 玩家                                                         |
| key         | string \| 字符串 | 存档变量Key，最大长度63位<br />实际读取时会在存档变量Key上增加前缀 “R” |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| real \| 实数 | 服务器上的存档变量Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetStoredReal](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetStoredReal.png)

**JASS** 
```JASS
native DzAPI_Map_GetServerValue takes player whichPlayer, string key returns string

function DzAPI_Map_GetStoredReal takes player whichPlayer, string key returns real
	local real value
	set key = "R" + key
	set value = S2R( DzAPI_Map_GetServerValue( whichPlayer, key ) )
	set key = null
	set whichPlayer = null
	return value
endfunction
	
call DzAPI_Map_GetStoredReal( Player(0), "variablename" )
```

**LUA**

<font color=gray>请使用 [读取服务器变量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1190 | 存档初始化加载失败 |

原文：[kkapi/DzAPI_Map_GetStoredReal.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetStoredReal.md)

---

### 读取服务器上的布尔变量

从服务器上获取布尔类型的变量数据 

##### 参数
| 参数名      | 类型             | 说明                                                         |
| :---------- | :--------------- | :----------------------------------------------------------- |
| whichPlayer | player \| 玩家   | 玩家                                                         |
| key         | string \| 字符串 | 存档变量Key，最大长度63位<br />实际读取时会在存档变量Key上增加前缀 “B” |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | 服务器上的存档变量Value |

##### 调用示例 

**WorldEdit Trigger**

![image-DzAPI_Map_GetStoredBoolean](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetStoredBoolean.png)

**JASS** 

```JASS
native DzAPI_Map_GetServerValue takes player whichPlayer, string key returns string

function DzAPI_Map_GetStoredBoolean takes player whichPlayer, string key returns boolean
	local boolean value
	set key = "B" + key
	set key = DzAPI_Map_GetServerValue( whichPlayer, key )
	if( key=="1" ) then
		set value = true
	else
		set value = false
	endif
	set key = null
	set whichPlayer = null
	return value
endfunction
	
call DzAPI_Map_GetStoredBoolean( Player(0), "variablename" )
```

**LUA**

<font color=gray>请使用 [读取服务器变量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerValue.md) 替代</font>

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1190 | 存档初始化加载失败 |

原文：[kkapi/DzAPI_Map_GetStoredBoolean.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetStoredBoolean.md)

---

### 存储服务器存档（区分大小写）

将变量存储到服务器，存档变量Key区分大小写。

数据保存时会受到开发者平台配置的写入规则限制（防刷分、只增等）。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 存档变量Key，最大长度63位，区分大小写 |
| value       | string \| 字符串 | 存档变量Value，最大长度63位 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_SaveServerArchive](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_SaveServerArchive.png)

**JASS**

```JASS
function DzAPI_Map_SaveServerArchive takes player whichPlayer, string key, string value returns nothing
    return RequestExtraBooleanData(39, whichPlayer, key, value, false, 0, 0, 0)
endfunction

call DzAPI_Map_SaveServerArchive(Player(0), "itemkey", "value")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_SaveServerArchive( whichPlayer,  key,  value )
    return japi.RequestExtraBooleanData(39, whichPlayer, key, value, false, 0, 0, 0)
end

DzAPI_Map_SaveServerArchive(jass.Player(0), "itemkey", "value")
```

##### 错误代码

| 代码 | 错误描述                           |
| ---- | :--------------------------------- |
| 1750 | 地图未开通服务器存档功能           |
| 1753 | 存档数据不一致                     |
| 1757 | 上传频率超限                       |
| 1758 | 超过每局最大值                     |
| 1191 | 存档变量Key长度超过64位            |
| 1192 | 存档数量超过上限                   |
| 1250 | 增加的值超出上限（服务器存档防刷） |

原文：[kkapi/DzAPI_Map_SaveServerArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SaveServerArchive.md)

---

### 读取服务器存档（区分大小写）

从服务器上读取变量数据，存档变量Key区分大小写。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 存档变量Key，最大长度63位，区分大小写 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 服务器上最新的存档变量Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_ServerArchive](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_ServerArchive.png)

**JASS**

```JASS
function DzAPI_Map_ServerArchive takes player whichPlayer, string key returns string
    return RequestExtraStringData(38, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_ServerArchive(Player(0), "itemkey")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_ServerArchive( whichPlayer,  key )
    return japi.RequestExtraStringData(38, whichPlayer, key, nil, false, 0, 0, 0)
end

DzAPI_Map_ServerArchive(jass.Player(0), "itemkey")
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1190 | 存档初始化加载失败 |

原文：[kkapi/DzAPI_Map_ServerArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_ServerArchive.md)

---

### 开始保存批量存档

将存档批量保存前先执行该触发

> 批量保存3步骤：1.[开始保存](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiBeginBatchSaveArchive.md)2.[增加条目](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiAddBatchSaveArchive.md)3.[结束保存](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiEndBatchSaveArchive.md)


##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |


##### 返回值
布尔值

##### 调用示例

**WorldEdit Trigger**

![image-KKApiBeginBatchSaveArchive](https://create.kkdzpt.com/kkapidoc/image-KKApiBeginBatchSaveArchive.png)

**JASS**

```JASS
function KKApiBeginBatchSaveArchive takes player whichPlayer returns boolean
    return RequestExtraBooleanData(102, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call KKApiBeginBatchSaveArchive( Player(0) )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiBeginBatchSaveArchive takes player whichPlayer returns boolean
    return japi.RequestExtraBooleanData(102, whichPlayer, null, null, false, 0, 0, 0)
endfunction

japi.KKApiBeginBatchSaveArchive( jass.Player(0) ) 
```

原文：[kkapi/KKApiBeginBatchSaveArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiBeginBatchSaveArchive.md)

---

### 批量存档增加条目

增加批量存档的条目，调用结束保存后条目会清空。

> 批量保存3步骤：1.[开始保存](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiBeginBatchSaveArchive.md)2.[增加条目](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiAddBatchSaveArchive.md)3.[结束保存](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiEndBatchSaveArchive.md)

##### 参数

| 参数名      | 类型   | 说明                   |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家           |
| key         | String \| 字符串 | key名        |
| value       | String \| 字符串 | value        |
| 区分大小写   | boolean\| 布尔值 | true=区分，false=不区分大小写       |




##### 返回值
布尔值

##### 调用示例

**WorldEdit Trigger**

![image-KKApiAddBatchSaveArchive](https://create.kkdzpt.com/kkapidoc/image-KKApiAddBatchSaveArchive.png)

**JASS**

```JASS
function KKApiAddBatchSaveArchive takes player whichPlayer, string key, string value, boolean caseInsensitive returns boolean
    return RequestExtraBooleanData(103, whichPlayer, key, value, caseInsensitive, 0, 0, 0)
endfunction

 call KKApiAddBatchSaveArchive( Player(0), "key", "value", false )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiAddBatchSaveArchive takes player whichPlayer, string key, string value, boolean caseInsensitive returns boolean
    return japi.RequestExtraBooleanData(103, whichPlayer, key, value, caseInsensitive, 0, 0, 0)
endfunction

japi.KKApiAddBatchSaveArchive( jass.Player(0), "key", "value", false )
```

原文：[kkapi/KKApiAddBatchSaveArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiAddBatchSaveArchive.md)

---

### 结束批量存档

放弃当前批量上传的key or 开始批量上传，调用后都会清空存档条目。

> 批量保存3步骤：1.[开始保存](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiBeginBatchSaveArchive.md)2.[增加条目](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiAddBatchSaveArchive.md)3.[结束保存](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiEndBatchSaveArchive.md)

##### 参数

| 参数名      | 类型   | 说明                   |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家           |
| 布尔值       | boolean\| 布尔值 | true=放弃本次上传，并清空条目，false=上报批量结果，并清空条目。     |




##### 返回值
布尔值

##### 调用示例

**WorldEdit Trigger**

![image-KKApiEndBatchSaveArchive](https://create.kkdzpt.com/kkapidoc/image-KKApiEndBatchSaveArchive.png)

**JASS**

```JASS
function KKApiEndBatchSaveArchive takes player whichPlayer, boolean abandon returns booleancaseInsensitive returns boolean
    return RequestExtraBooleanData(104, whichPlayer, null, null, abandon, 0, 0, 0)
endfunction

 call KKApiEndBatchSaveArchive( Player(0), false )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiEndBatchSaveArchive takes player whichPlayer, boolean abandon returns booleancaseInsensitive returns boolean
    return japi.RequestExtraBooleanData(104, whichPlayer, null, null, abandon, 0, 0, 0)
endfunction

japi.KKApiEndBatchSaveArchive( jass.Player(0), false )
```

原文：[kkapi/KKApiEndBatchSaveArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiEndBatchSaveArchive.md)

---

## 商业化

> 平台有成熟的地图商业化模式，开发者可以在[KK开发者平台](https://create.reckfeng.com)设立道具，并将道具放置在平台商城进行售卖以赚取收益。
> 
> 玩家在平台商城进行购买道具、或通过平台活动获得的道具都会进入玩家的背包，地图内可通过背包相关接口实现自定义功能。

###### 玩家背包中的地图商城道具：

原文：[menu_kkapi_commercialization.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_commercialization.md)

---

### 玩家是否拥有地图商城道具

检测玩家背包中是否拥该道具且处于有效状态。

已过期的时效性道具、剩余数量为0的数量型道具均视为无效；

##### 参数
| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 地图商城道具key，需要先在[KK开发者平台](https://create.reckfeng.com)完成道具配置 |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | true 表示拥有，false 表示未拥有 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_HasMallItem](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_HasMallItem.png)

**JASS**

```JASS
native DzAPI_Map_HasMallItem takes player whichPlayer, string key returns boolean

call DzAPI_Map_HasMallItem( Player(0), "itemkey" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzAPI_Map_HasMallItem( jass.Player(0), "itemkey" ) 
```

原文：[kkapi/DzAPI_Map_HasMallItem.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_HasMallItem.md)

---

### 玩家地图商城道具剩余数量

获取玩家背包中指定道具的剩余数量。

##### 参数
| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  |
| key         | string \| 字符串 | 地图商城道具key，需要先在[KK开发者平台](https://create.reckfeng.com)完成道具配置 |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 剩余数量 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetMallItemCount](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetMallItemCount.png)

**JASS**

```JASS
function DzAPI_Map_GetMallItemCount takes player whichPlayer, string key returns integer
	return RequestExtraIntegerData( 41, whichPlayer, key, null, false, 0, 0, 0 )
endfunction
	
call DzAPI_Map_GetMallItemCount( Player(0), "itemkey" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetMallItemCount(whichPlayer, key)
    return japi.RequestExtraIntegerData( 41, whichPlayer, key, nil, false, 0, 0, 0 )
end

DzAPI_Map_GetMallItemCount( jass.Player(0), "itemkey" ) 
```

原文：[kkapi/DzAPI_Map_GetMallItemCount.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMallItemCount.md)

---

### 使用地图商城道具（数量型）

扣减玩家背包中的数量消耗型道具，可以多次调用

##### 参数

| 参数名      | 类型             | 说明         |
| :---------- | :--------------- | :----------- |
| whichPlayer | player \| 玩家   | 玩家         |
| key         | string \| 字符串 | 地图商城道具key，需要先在[KK开发者平台](https://create.reckfeng.com)完成道具配置 |
| count       | interger \| 整数 | 要扣减的数量 |

##### 返回结果

| 类型              | 说明                                            |
| :---------------- | :---------------------------------------------- |
| boolean \| 布尔值 | true 扣减成功<br />false 剩余数量不足，扣减失败 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_ConsumeMallItem](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_ConsumeMallItem.png)

**JASS**

```JASS
function DzAPI_Map_ConsumeMallItem takes player whichPlayer, string key, integer count returns boolean
	return RequestExtraBooleanData( 42, whichPlayer, key, null, false, count, 0, 0 )
endfunction
	
call DzAPI_Map_ConsumeMallItem( Player(0), "itemkey", 1 )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_ConsumeMallItem(whichPlayer, key, count)
    return japi.RequestExtraBooleanData( 42, whichPlayer, key, nil, false, count, 0, 0 )
end

DzAPI_Map_ConsumeMallItem( jass.Player(0), "itemkey", 1 ) 
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1259 | 道具剩余数量不足 |

原文：[kkapi/DzAPI_Map_ConsumeMallItem.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_ConsumeMallItem.md)

---

### 使用地图商城道具（局数型）

扣减玩家背包中的局数型道具1个，多次对同一个道具调用也只扣减1次。

需先通过[玩家地图商城道具剩余数量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMallItemCount)确保玩家背包中的道具剩余数量大于0。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 地图商城道具key，需要先在[KK开发者平台](https://create.reckfeng.com)完成道具配置 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_UseConsumablesItem](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_UseConsumablesItem.png)

**JASS**

```JASS
native DzAPI_Map_UseConsumablesItem takes player whichPlayer, string key returns nothing

call DzAPI_Map_UseConsumablesItem( Player(0), "itemkey" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzAPI_Map_UseConsumablesItem( jass.Player(0), "itemkey" ) 
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1259 | 道具剩余数量不足 |

原文：[kkapi/DzAPI_Map_UseConsumablesItem.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_UseConsumablesItem.md)

---

### 打开地图商城道具购买界面

打开游戏内置商城的道具购买页面，用于实现游戏过程中的消费引导场景，需已在商城上架对应商品。

购买成功后可通过[玩家实时获得地图商城道具事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterMallItemSyncData.md)实现在游戏内立即生效。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 地图商城道具key，需要先在[KK开发者平台](https://create.reckfeng.com)完成道具配置 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_OpenMall](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_OpenMall.png)

**JASS**

```JASS
function DzAPI_Map_OpenMall takes player whichPlayer, string whichKey returns boolean
    return RequestExtraBooleanData(66, whichPlayer, whichKey, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_OpenMall(Player(0), "heroGuanYu")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_OpenMall( whichPlayer,  whichKey )
    return japi.RequestExtraBooleanData(66, whichPlayer, whichKey, nil, false, 0, 0, 0)
end

DzAPI_Map_OpenMall(jass.Player(0), "heroGuanYu")
```

原文：[kkapi/DzAPI_Map_OpenMall.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_OpenMall.md)

---

### 使用U币快速购买地图商城道具

扣除玩家U币购买指定地图商城道具，需已在商城上架对应商品（商品信息中的**道具和数量**与接口所请求的参数一致）。

扣款前需要玩家进行二次确认，如果前一次购买的确认提示框未关闭的情况下再次调用此接口，新的调用无效。

购买成功后可通过[玩家实时获得地图商城道具事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterMallItemSyncData.md)实现在游戏内立即生效。

##### 访问授权限制

高级接口，需要授权后才允许使用。

##### 参数

| 参数名      | 类型             | 说明         |
| :---------- | :--------------- | :----------- |
| whichPlayer | player \| 玩家   | 玩家         |
| key         | string \| 字符串 | 地图商城道具key  |
| count       | integer \| 整数  | 数量     |
| seconds     | integer \| 整数  | 购买确认提示框倒计时（秒数），倒计时结束视为放弃购买。最小5秒，最大99秒，0表示始终显示 |


##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 |  |


##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_QuickBuy](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_QuickBuy.png)

**JASS**

```JASS
function DzAPI_Map_QuickBuy takes player whichPlayer, string key, integer count, integer seconds returns boolean
	return RequestExtraBooleanData(72, whichPlayer, key, null, false, count, seconds, 0)
endfunction

call DzAPI_Map_QuickBuy(Player(0), "HealthPotion", 1, 0)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_QuickBuy( whichPlayer,key,count,seconds )
	return japi.RequestExtraBooleanData(72, whichPlayer, key, nil, false, count, seconds, 0)
end

DzAPI_Map_QuickBuy(jass.Player(0), "HealthPotion", 1, 0)
```

原文：[kkapi/DzAPI_Map_QuickBuy.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_QuickBuy.md)

---

### 关闭U币快速购买界面

关闭U币快速购买的购买确认提示窗口，结合[使用U币快速购买地图商城道具](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_QuickBuy.md)使用。

适用于游戏场景切换后，之前已弹出的购买提示不再适用的情况。

比如游戏开始前1分钟可以使用点将卡更换英雄，1分钟内可提示玩家购买英雄更换道具，超出1分钟后关闭提示防止玩家误购买。

##### 访问授权限制

高级接口，需要授权后才允许使用。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_CancelQuickBuy](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_CancelQuickBuy.png)

**JASS**

```JASS
function DzAPI_Map_CancelQuickBuy takes player whichPlayer returns boolean
	return RequestExtraBooleanData(73, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_CancelQuickBuy(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_CancelQuickBuy( whichPlayer )
    return japi.RequestExtraBooleanData(73, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_CancelQuickBuy(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_CancelQuickBuy.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_CancelQuickBuy.md)

---

### 玩家实时获得地图商城道具事件

玩家背包中新获得了当前地图道具的回调通知事件，用于商城购买成功后在游戏内立即生效。

可通过事件[事件响应-实时获得地图商城道具的玩家](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerMallItemPlayer.md)和[事件响应-实时获得的地图商城道具](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerMallItem.md)获取事件响应数据。

##### 调用示例

**WorldEdit Trigger**

![image-DzTriggerRegisterMallItemSyncData](https://create.kkdzpt.com/kkapidoc/image-DzTriggerRegisterMallItemSyncData.png)

**JASS**

```JASS
native DzTriggerRegisterSyncData takes trigger trig, string prefix, boolean server returns nothing

function DzTriggerRegisterMallItemSyncData takes trigger trig returns nothing
	call DzTriggerRegisterSyncData(trig, "DZMIA", true)
endfunction
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzTriggerRegisterMallItemSyncData(trig)
	japi.DzTriggerRegisterSyncData(trig, "DZMIA", true)
end 
```

原文：[kkapi/DzTriggerRegisterMallItemSyncData.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterMallItemSyncData.md)

---

### 事件响应 - 实时获得地图商城道具的玩家

获取是哪位玩家获得了地图商城道具。

仅限在[玩家实时获得地图商城道具事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterMallItemSyncData.md)内使用。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| player \| 玩家 | 获得地图商城道具的玩家 |

##### 调用示例

**WorldEdit Trigger**

![image-DzGetTriggerMallItemPlayer](https://create.kkdzpt.com/kkapidoc/image-DzGetTriggerMallItemPlayer.png)

**JASS**

```JASS
native DzGetTriggerSyncPlayer takes nothing returns player

function DzGetTriggerMallItemPlayer takes nothing returns player
	return DzGetTriggerSyncPlayer()
endfunction

call DzGetTriggerMallItemPlayer()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzGetTriggerMallItemPlayer()
	return japi.DDzGetTriggerSyncPlayer()
end

DzGetTriggerMallItemPlayer()
```

原文：[kkapi/DzGetTriggerMallItemPlayer.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerMallItemPlayer.md)

---

### 事件响应 - 实时获得的地图商城道具

获取背包中新获得的地图商城道具Key。

仅限在[玩家实时获得地图商城道具事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterMallItemSyncData.md)内使用。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 玩家所获得的地图商城道具key |

##### 调用示例

**WorldEdit Trigger**

![image-DzGetTriggerMallItem](https://create.kkdzpt.com/kkapidoc/image-DzGetTriggerMallItem.png)

**JASS**

```JASS
native DzGetTriggerSyncData takes nothing returns string

//获取购买的商品key
function DzGetTriggerMallItem takes nothing returns string
	return DzGetTriggerSyncData()
endfunction

call DzGetTriggerMallItem()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzGetTriggerMallItem()
	return japi.DzGetTriggerSyncData()
end

DzGetTriggerMallItem()
```

原文：[kkapi/DzGetTriggerMallItem.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerMallItem.md)

---

## 游戏环境及配置

原文：[menu_kkapi_game_environment.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_game_environment.md)

---

### 地图配置参数

获取当前地图在[KK开发者平台](https://create.reckfeng.com)配置的地图参数（原只读类型的地图全局存档），可以通过此接口实现节日活动开关、口令等功能。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| key         | string \| 字符串 | [KK开发者平台](https://create.reckfeng.com)所配置的参数Key |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | Key当前对应的参数Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetMapConfig](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetMapConfig.png)

**JASS**

```JASS
native DzAPI_Map_GetMapConfig takes string key returns string

call DzAPI_Map_GetMapConfig("EnableFreeVIP")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetMapConfig( key )
    return japi.RequestExtraStringData(21, nil, key, nil, false, 0, 0, 0)
end

DzAPI_Map_GetMapConfig("EnableFreeVIP")
```

原文：[kkapi/DzAPI_Map_GetMapConfig.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMapConfig.md)

---

### 本局游戏是否天梯排位赛

本局游戏是否通过RPG天梯启动，如果地图配置了多个天梯模式，可通过[获取本局游戏的地图模式](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMatchType.md)接口获取具体选定的是哪一个天梯模式。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示本局游戏是天梯比赛，False 表示不是天梯比赛 |


##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsRPGLadder](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsRPGLadder.png)

**JASS**

```JASS
native DzAPI_Map_IsRPGLadder takes nothing returns boolean

call DzAPI_Map_IsRPGLadder()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzAPI_Map_IsRPGLadder()
```

原文：[kkapi/DzAPI_Map_IsRPGLadder.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsRPGLadder.md)

---

### 本局游戏是否快速匹配

本局游戏是否通过RPG快速匹配启动，如果地图配置了多个匹配模式，可通过[获取本局游戏的地图模式](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMatchType.md)接口获取具体选定的是哪一个匹配模式。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示本局游戏是RPG快速匹配， False 表示不是快速匹配 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsRPGQuickMatch](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsRPGQuickMatch.png)

**JASS**

```JASS
function DzAPI_Map_IsRPGQuickMatch takes nothing returns boolean
	return RequestExtraBooleanData(40, null, null, null, false, 0, 0, 0)
endfunction

DzAPI_Map_IsRPGQuickMatch()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsRPGQuickMatch()
    return japi.RequestExtraBooleanData(40, nil, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_IsRPGQuickMatch()
```

原文：[kkapi/DzAPI_Map_IsRPGQuickMatch.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsRPGQuickMatch.md)

---

### 本局游戏的地图模式

获取本局游戏所选择地图模式，开发者可以在[KK开发者平台](https://create.reckfeng.com)自行配置地图模式（包括天梯排位赛模式、快速匹配模式、建房间时房主所选定的地图模式）。

##### 参数
无 

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 本局游戏所选择的地图模式Key，该Key在[KK开发者平台](https://create.reckfeng.com)进行配置。 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetMatchType](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetMatchType.png)

**JASS**

```JASS
native DzAPI_Map_GetMatchType takes nothing returns integer

call DzAPI_Map_GetMatchType()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetMatchType( )
    return japi.RequestExtraIntegerData(13, nil, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetMatchType()
```

原文：[kkapi/DzAPI_Map_GetMatchType.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMatchType.md)

---

### 本局游戏的开始时间

获取本局游戏开始时的服务器时间。

##### 参数

无

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | Unix时间戳 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetGameStartTime](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetGameStartTime.png)

**JASS**

```JASS
native DzAPI_Map_GetGameStartTime takes nothing returns integer

call DzAPI_Map_GetGameStartTime()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetGameStartTime()
    return japi.RequestExtraIntegerData(11,nil, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetGameStartTime()
```

原文：[kkapi/DzAPI_Map_GetGameStartTime.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetGameStartTime.md)

---

### 玩家是否为真实玩家

当开启匹配模式的虚拟电脑玩家(AI)补位功能后，可通过此接口判定是否真实玩家。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示是真实玩家，False 表示是虚拟电脑玩家(AI) |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsPlayer](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsPlayer.png)

**JASS**

```JASS
function DzAPI_Map_IsPlayer takes player whichPlayer returns boolean
    return RequestExtraBooleanData(55, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_IsPlayer(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsPlayer( whichPlayer )
    return japi.RequestExtraBooleanData(55, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_IsPlayer(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_IsPlayer.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsPlayer.md)

---

### 本局游戏是否处于平台自测服

获取当前游戏局所处的平台环境。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示当前地图在地图测试服， False 表示不是 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsMapTest](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsMapTest.png)

**JASS**

```JASS
function DzAPI_Map_IsMapTest takes nothing returns boolean
    return RequestExtraBooleanData(74, null, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_IsMapTest()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsMapTest()
    return japi.RequestExtraBooleanData(74, nil, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_IsMapTest()
```

原文：[kkapi/DzAPI_Map_IsMapTest.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsMapTest.md)

---

### 本局游戏是否处于RPG游戏大厅

获取当前游戏局是否通过RPG游戏大厅启动。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示当前本局游戏是通过RPG游戏大厅启动（包括测试大厅）<br /> False 表示不是，即通过自定义房间选择本地地图启动 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsRPGLobby](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsRPGLobby.png)

**JASS**

```JASS
function DzAPI_Map_IsRPGLobby takes nothing returns boolean
    return RequestExtraBooleanData(10, null, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_IsRPGLobby()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsRPGLobby()
    return japi.RequestExtraBooleanData(10, nil, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_IsRPGLobby()
```

原文：[kkapi/DzAPI_Map_IsRPGLobby.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsRPGLobby.md)

---

### 玩家服务器存档是否读取成功

判断本局游戏中玩家的服务器存档是否正确加载。

加载失败一般是玩家网络不稳定导致，重开一局游戏即可解决，推荐在游戏开始时进行检查。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 服务器存档加载成功，False 服务器存档加载失败 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetPlayerServerValueSuccess](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetPlayerServerValueSuccess.png)

**JASS**

```JASS
native DzAPI_Map_GetServerValueErrorCode takes player whichPlayer returns integer

function GetPlayerServerValueSuccess takes player whichPlayer returns boolean
    if ( DzAPI_Map_GetServerValueErrorCode(whichPlayer) == 0 ) then
        return true
    else
        return false
    endif
endfunction 

call GetPlayerServerValueSuccess( Player(0)  )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function GetPlayerServerValueSuccess(whichPlayer)
    if ( DzAPI_Map_GetServerValueErrorCode(whichPlayer) == 0 ) then
        return true
    else
        return false
    end
end 

GetPlayerServerValueSuccess( jass.Player(0) ) 
```

原文：[kkapi/DzAPI_Map_GetPlayerServerValueSuccess.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetPlayerServerValueSuccess.md)

---

### 是否在平台正常游戏中

获取当前游戏局是正常游戏，还是处于观战/录像。

!> 此API如使用不当可能引发无法观战/看录像，建议仅用于本地UI相关的逻辑处理。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示是正常游戏 <br /> False 表示是观战或录像 |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiIsGameMode](https://create.kkdzpt.com/kkapidoc/image-KKApiIsGameMode.png)

**JASS**

```JASS
function KKApiIsGameMode takes nothing returns boolean
	return RequestExtraBooleanData(90, null, null, null, false, 0, 0, 0)
endfunction

call KKApiIsGameMode()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiIsGameMode()
	return japi.RequestExtraBooleanData(90, nil, nil, nil, false, 0, 0, 0)
end

KKApiIsGameMode()
```

原文：[kkapi/KKApiIsGameMode.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiIsGameMode.md)

---

### 玩家地图商城道具是否读取成功

判断本局游戏中玩家背包道具是否正确加载。

加载失败一般是玩家网络不稳定导致，重开一局游戏即可解决，推荐在游戏开始时进行检查。

##### 参数

| 参数名      | 类型   | 说明                  |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家                  | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True加载成功，False加载失败 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_DzAPI_Map_PlayerLoadedItems](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_PlayerLoadedItems.png)

**JASS**

```JASS
function DzAPI_Map_PlayerLoadedItems takes player whichPlayer returns boolean
    return RequestExtraBooleanData(77, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_PlayerLoadedItems( Player(0)  )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_PlayerLoadedItems(whichPlayer)
    return japi.RequestExtraBooleanData(77, whichPlayer, nil, nil, false, 0, 0, 0)
end 

DzAPI_Map_PlayerLoadedItems( jass.Player(0) ) 
```

原文：[kkapi/DzAPI_Map_PlayerLoadedItems.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_PlayerLoadedItems.md)

---

## 玩家行为和玩家信息

> 允许开发者在地图内获取到玩家的信息及行为数据，方便开发者设计一些平台和游戏内联动玩法，更好的促进玩家活跃和留存。

###### 平台级：

原文：[menu_kkapi_profile_behavior.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_profile_behavior.md)

---

### 玩家是否平台尊享会员

判断玩家是否平台的尊享会员。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 表示是平台尊享会员，False 表示不是会员或会员已过期。 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsPlatformVIP](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsPlatformVIP.png)

**JASS**

```JASS
native DzAPI_Map_GetPlatformVIP takes player whichPlayer returns integer

function DzAPI_Map_IsPlatformVIP takes player whichPlayer returns boolean
    return DzAPI_Map_GetPlatformVIP(whichPlayer) > 0
endfunction

call DzAPI_Map_IsPlatformVIP(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsPlatformVIP( whichPlayer )
    return japi.RequestExtraIntegerData(30, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_IsPlatformVIP(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_IsPlatformVIP.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsPlatformVIP.md)

---

### 玩家是否装备指定平台装饰

检查玩家是否装备着指定平台装饰（仅限平台和地图的合作装饰）。

##### 访问授权限制

高级接口，仅限有跟平台推出合作装饰的地图使用，装饰道具ID请联系平台运营接口人提供。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| skinType | integer\| 整数 | 装饰类型，头像=1、边框=2、称号=3、底纹=4 |
| id | integer\|整数 | 装饰道具ID |


##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True 装备了该道具，False 未装备该道具 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsPlayerUsingSkin](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsPlayerUsingSkin.png)

**JASS**

```JASS
function DzAPI_Map_IsPlayerUsingSkin takes player whichPlayer, integer skinType, integer id returns boolean
    return RequestExtraBooleanData(64, whichPlayer, null, null, false, skinType, id, 0)
endfunction

call DzAPI_Map_IsPlayerUsingSkin(Player(0), 1, 100000)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsPlayerUsingSkin( whichPlayer,  skinType,  id )
    return japi.RequestExtraBooleanData(64, whichPlayer, nil, nil, false, skinType, id, 0)
end

DzAPI_Map_IsPlayerUsingSkin(jass.Player(0), 1, 100000)
```

原文：[kkapi/DzAPI_Map_IsPlayerUsingSkin.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsPlayerUsingSkin.md)

---

### 玩家在KK对战平台的完整昵称

获取玩家在KK对战平台的完整昵称（基础昵称#编号）。 

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 完整昵称 <br /> 注：在本地开发环境中调用此API返回值为null。 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetPlayerUserName](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetPlayerUserName.png)

**JASS**

```JASS
function DzAPI_Map_GetPlayerUserName takes player whichPlayer returns string 
    return RequestExtraStringData(81, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_GetPlayerUserName(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetPlayerUserName( whichPlayer )
    return japi.RequestExtraStringData(81, whichPlayer, null, null, false, 0, 0, 0)
end

DzAPI_Map_GetPlayerUserName(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetPlayerUserName.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetPlayerUserName.md)

---

### 获取玩家的身份类型

获取当前玩家在平台的身份类型（主播/职业选手）

##### 参数

| 参数名         | 类型          | 说明          |
| :---------- | :---------- | :---------- |
| whichPlayer | player\|玩家  | 玩家          |
| id          | integer\|整数 | 3=主播，4=职业选手 |

##### 返回值

布尔值

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-KKApiPlayerIdentityType.png)

**JASS**

```JASS
function KKApiPlayerIdentityType takes player whichPlayer, integer id returns boolean
return RequestExtraBooleanData(92, whichPlayer, null, null, false, id, 0, 0)
endfunction

call KKApiPlayerIdentityType(Player(0), 3)
```

**LUA**

```LUA
local japi = require "jass.japi"

KKApiPlayerIdentityType(jass.Player(0), 3)
```

原文：[kkapi/KKApiPlayerIdentityType.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiPlayerIdentityType.md)

---

### 玩家是否当前地图作者

判断指定玩家是否为本地图的作者。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 |  |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_IsAuthor](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_IsAuthor.png)

**JASS**

```JASS
function DzAPI_Map_IsAuthor takes player whichPlayer returns boolean
    return RequestExtraBooleanData(50, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_IsAuthor(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_IsAuthor( whichPlayer )
    return japi.RequestExtraBooleanData(50, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_IsAuthor(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_IsAuthor.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_IsAuthor.md)

---

### 玩家地图等级

获取玩家在当前地图的地图等级。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 地图等级 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetMapLevel](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetMapLevel.png)

**JASS**

```JASS
native DzAPI_Map_GetMapLevel takes player whichPlayer returns integer

call DzAPI_Map_GetMapLevel(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetMapLevel( whichPlayer )
    return japi.RequestExtraIntegerData(3, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetMapLevel(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetMapLevel.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMapLevel.md)

---

### 玩家累计游戏局数

获取玩家在当前地图的累计游戏局数。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 累计游戏局数 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_PlayedGames.md](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_PlayedGames.png)

**JASS**

```JASS
function DzAPI_Map_PlayedGames takes player whichPlayer returns boolean
    return RequestExtraIntegerData(45, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_PlayedGames(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_PlayedGames( whichPlayer )
    return japi.RequestExtraIntegerData(45, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_PlayedGames(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_PlayedGames.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_PlayedGames.md)

---

### 玩家累计游戏时长

获取玩家在当前地图的累计游戏时长

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 累计游戏时长，单位为秒 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_MapsTotalPlayed](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_MapsTotalPlayed.png)

**JASS**

```JASS
function DzAPI_Map_MapsTotalPlayed takes player whichPlayer returns integer
    return RequestExtraIntegerData(56, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_MapsTotalPlayed(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_MapsTotalPlayed( whichPlayer )
    return japi.RequestExtraIntegerData(56, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_MapsTotalPlayed(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_MapsTotalPlayed.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_MapsTotalPlayed.md)

---

### 玩家在地图等级排行榜上的排名

获取玩家在当前地图的地图等级排行榜上的排名。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 玩家在地图等级排行榜的排名，如果名次大于100，则返回0 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetMapLevelRank](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetMapLevelRank.png)

**JASS**

```JASS
function DzAPI_Map_GetMapLevelRank takes player whichPlayer returns integer
    return RequestExtraIntegerData(18, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_GetMapLevelRank(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetMapLevelRank( whichPlayer )
    return japi.RequestExtraIntegerData(18, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetMapLevelRank(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetMapLevelRank.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetMapLevelRank.md)

---

### 玩家在地图社区上的互动数据

获取玩家在当前地图的社区内的行为统计数据及身份数据。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| whichData | integer \| 整数 | 0=累计获得赞数，1=精华帖数量，2=发表回复次数，3=收到的欢乐数，4=是否发过贴子，5=是否版主，6=主题数量 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | whichData是**是否版主**时，1=版主，0=不是版主<br />whichData是**其他**项时，为对应数据项的统计数量 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetForumData](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetForumData.png)

**JASS**

```JASS
function DzAPI_Map_GetForumData takes player whichPlayer, integer whichData returns integer
    return RequestExtraIntegerData(65, whichPlayer, null, null, false, whichData, 0, 0)
endfunction

call DzAPI_Map_GetForumData(Player(0), 1)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetForumData( whichPlayer,  whichData )
    return japi.RequestExtraIntegerData(65, whichPlayer, nil, nil, false, whichData, 0, 0)
end

DzAPI_Map_GetForumData(Player(0), 1) 
```

原文：[kkapi/DzAPI_Map_GetForumData.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetForumData.md)

---

### 玩家签到天数

获取玩家在指定地图的地图签到数据。

##### 参数

| 参数名      | 类型           | 说明                                                        |
| :---------- | :------------- | :---------------------------------------------------------- |
| whichPlayer | player \| 玩家 | 玩家 |
| id          | integer\|整数  | 统计分类：0=总签到天数，1=最多连续签到天数，2=当前连续签到天数 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 签到天数 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_ContinuousCount](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_ContinuousCount.png)

**JASS**

```JASS
function DzAPI_Map_ContinuousCount takes player whichPlayer, integer id returns integer
    return RequestExtraIntegerData(54, whichPlayer, null, null, false, id, 0, 0)
endfunction

call DzAPI_Map_ContinuousCount(Player(0), 0)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_MapsLevel( whichPlayer, id )
    return RequestExtraIntegerData(54, whichPlayer, nil, nil, false, id, 0, 0)
end 

DzAPI_Map_ContinuousCount(jass.Player(0), 0)
```

原文：[kkapi/DzAPI_Map_ContinuousCount.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_ContinuousCount.md)

---

### 玩家抽取地图宝箱总次数

获取玩家在当前地图下所有宝箱的抽取次数（10连抽算10次）。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 宝箱抽取次数 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetLotteryUsedCount](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetLotteryUsedCount.png)

**JASS**

```JASS
function DzAPI_Map_GetLotteryUsedCount takes player whichPlayer returns integer
    return RequestExtraIntegerData(68, whichPlayer, null, null, false, 0, 0, 0)
        + RequestExtraIntegerData(68, whichPlayer, null, null, false, 1, 0, 0)
        + RequestExtraIntegerData(68, whichPlayer, null, null, false, 2, 0, 0)
endfunction

call DzAPI_Map_GetLotteryUsedCount(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetLotteryUsedCount( whichPlayer )
    return japi.RequestExtraIntegerData(68, whichPlayer, nil, nil, false, 0, 0, 0) 
        + japi.RequestExtraIntegerData(68, whichPlayer, nil, nil, false, 1, 0, 0) 
        + japi.RequestExtraIntegerData(68, whichPlayer, nil, nil, false, 2, 0, 0)
end

DzAPI_Map_GetLotteryUsedCount(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetLotteryUsedCount.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetLotteryUsedCount.md)

---

### 玩家抽取指定地图宝箱次数

获取玩家在当前地图下某一个宝箱的抽取次数（10连抽算10次）。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| index | integer \| 整数  | 0=第一个宝箱（默认宝箱），1=第二个宝箱，2=第三个宝箱    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 宝箱抽取次数 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetLotteryUsedCountEx](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetLotteryUsedCountEx.png)

**JASS**

```JASS
function DzAPI_Map_GetLotteryUsedCountEx takes player whichPlayer,integer index returns integer
    return RequestExtraIntegerData(68, whichPlayer, null, null, false, index, 0, 0)
endfunction

call DzAPI_Map_GetLotteryUsedCountEx(Player(0), 0)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetLotteryUsedCountEx( whichPlayer, index )
    return japi.RequestExtraIntegerData(68, whichPlayer, nil, nil, false, index, 0, 0)
end

DzAPI_Map_GetLotteryUsedCountEx(jass.Player(0), 0)
```

原文：[kkapi/DzAPI_Map_GetLotteryUsedCountEx.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetLotteryUsedCountEx.md)

---

### 玩家最近一次上安利墙时间

获取玩家最近一次在当前地图的优质评论被推荐上安利墙的时间，

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | Unix时间戳 |


##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetLastRecommendTime](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetLastRecommendTime.png)

**JASS**

```JASS
function DzAPI_Map_GetLastRecommendTime takes player whichPlayer returns integer
    return RequestExtraIntegerData(67, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_GetLastRecommendTime(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetLastRecommendTime( whichPlayer )
    return japi.RequestExtraIntegerData(67, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetLastRecommendTime(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetLastRecommendTime.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetLastRecommendTime.md)

---

### 玩家本局游戏距上一局游戏的时间差

查询该玩家上次玩游戏时间至本次玩游戏时间的差值，可以利用此接口实现离线收益之类的功能。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 时间差，单位为秒 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetSinceLastPlayedSeconds](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetSinceLastPlayedSeconds.png)

**JASS**

```JASS
function DzAPI_Map_GetSinceLastPlayedSeconds takes player whichPlayer returns integer
	return RequestExtraIntegerData(70, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_GetSinceLastPlayedSeconds(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetSinceLastPlayedSeconds( whichPlayer )
    call japi.RequestExtraIntegerData(70, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetSinceLastPlayedSeconds(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetSinceLastPlayedSeconds.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetSinceLastPlayedSeconds.md)

---

### 玩家天梯等级

获取玩家在当前游戏局所采用的天梯模式下的天梯等级，仅天梯模式下的游戏局有效。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 取值1~25，青铜V是1级，青铜IV是2级，依次类推。 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetLadderLevel](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetLadderLevel.png)

**JASS**

```JASS
function DzAPI_Map_GetLadderLevel takes player whichPlayer returns integer
    return RequestExtraIntegerData(14, whichPlayer, null, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_GetLadderLevel(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetLadderLevel( whichPlayer )
    return japi.RequestExtraIntegerData(14, whichPlayer, nil, nil, false, 0, 0, 0)
end

DzAPI_Map_GetLadderLevel(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetLadderLevel.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetLadderLevel.md)

---

### 玩家天梯排名

获取玩家在当前游戏局所采用的天梯模式下的天梯排名，仅天梯模式下的游戏局有效。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 玩家的天梯排名，如果排名大于1000则返回0 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetLadderRank](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetLadderRank.png)

**JASS**

```JASS
native DzAPI_Map_GetLadderRank takes player whichPlayer returns integer

call DzAPI_Map_GetLadderRank(Player(0))
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetLadderRank( whichPlayer )
    return japi.RequestExtraIntegerData(17, whichPlayer, nil, nil, false, 0, 0, 0)
end

call DzAPI_Map_GetLadderRank(jass.Player(0))
```

原文：[kkapi/DzAPI_Map_GetLadderRank.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetLadderRank.md)

---

### 玩家标记

获取玩家在当前地图上的身份标记（当前是否回流用户、是否收藏地图）。

回流用户说明:
* 玩家距上一次游戏时间>14天 ,则为流失用户
* 流失用户上线进行一局游戏后，会标记回流时间为当日0:00，同时在7日（包含当天)内为回流用户

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| label    | integer \| 整数 | 标记类型，8=玩家是否当前地图的回流用户，16=玩家是否收藏当前地图 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 |  |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_PlayerFlags](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_PlayerFlags.png)

**JASS**

```JASS
function DzAPI_Map_PlayerFlags takes player whichPlayer, integer label returns boolean
	return RequestExtraBooleanData(53, whichPlayer, null, null, false, label, 0, 0)
endfunction

call DzAPI_Map_PlayerFlags(Player(0), 16)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_PlayerFlags( whichPlayer,  label )
    return japi.RequestExtraBooleanData(53, whichPlayer, nil, nil, false, label, 0, 0)
end

japi.DzAPI_Map_PlayerFlags(jass.Player(0), 16)
```

原文：[kkapi/DzAPI_Map_PlayerFlags.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_PlayerFlags.md)

---

### 获取玩家平台ID

返回一个32位的字符串

##### 参数

| 参数名 | 类型         | 说明    |
| :-- | :--------- | :---- |
| 玩家  | player\|玩家 | 获取的玩家 |

##### 返回值

字符串

##### 调用示例

![image-KKApiPlayerGUID](https://create.kkdzpt.com/kkapidoc/image-KKApiPlayerGUID.png)

**WorldEdit Trigger**

**JASS**

```JASS
function KKApiPlayerGUID takes player whichPlayer returns string
    return RequestExtraStringData(93, whichPlayer, null, null, false, 0, 0, 0)
endfunction

local string playerid = KKApiPlayerGUID(Player(0))
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

function KKApiPlayerGUID takes player whichPlayer returns string
    return japi.RequestExtraStringData(93, whichPlayer, null, null, false, 0, 0, 0)
endfunction

local playerid = japi.KKApiPlayerGUID(jass.Player(0))
```

原文：[kkapi/KKApiPlayerGUID.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiPlayerGUID.md)

---

### 获取玩家地图任务状态

获取玩家地图任务状态，需要先在作者之家创建地图任务并生成任务ID。

##### 参数

| 参数名  | 类型          | 说明                             |
| :--- | :---------- | :----------------------------- |
| 玩家   | player\|玩家  | 判断的玩家                          |
| 任务ID | integer\|整数 | 任务ID，通过作者之家创建任务时，勾选后任务数据获取后生成。 |
| 任务状态 | integer\|整数 | 未开始=0，进行中=1，已完成=2              |

##### 返回值

布尔值

##### 调用示例

![image-KKApiIsTaskInProgress](https://create.kkdzpt.com/kkapidoc/image-KKApiIsTaskInProgress.png)

**WorldEdit Trigger**

**JASS**

```JASS
function KKApiIsTaskInProgress takes player whichPlayer,integer setIndex,integer taskstat returns boolean
    return RequestExtraIntegerData(94, whichPlayer, null, null, false, setIndex, 0, 0)==taskstat
endfunction

local boolean quest = KKApiIsTaskInProgress(Player(0), 1, 0) 
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

function KKApiIsTaskInProgress takes player whichPlayer,integer setIndex,integer taskstat returns boolean
     return japi.RequestExtraIntegerData(94, whichPlayer, null, null, false, setIndex, 0, 0)==taskstat
endfunction

local quest = japi.KKApiIsTaskInProgress(jass.Player(0), 1, 0) 
```

原文：[kkapi/KKApiIsTaskInProgress.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiIsTaskInProgress.md)

---

### 获取玩家任务当前进度

获取玩家地图任务当前进度，需要先在作者之家创建地图任务并生成任务ID。

##### 参数

| 参数名  | 类型          | 说明                             |
| :--- | :---------- | :----------------------------- |
| 玩家   | player\|玩家  | 判断的玩家                          |
| 任务ID | integer\|整数 | 任务ID，通过作者之家创建任务时，勾选后任务数据获取后生成。 |

##### 返回值

整数

##### 调用示例

![image-KKApiQueryTaskCurrentProgress](https://create.kkdzpt.com/kkapidoc/image-KKApiQueryTaskCurrentProgress.png)

**WorldEdit Trigger**

**JASS**

```JASS
function KKApiQueryTaskCurrentProgress takes player whichPlayer, integer setIndex returns integer
        return RequestExtraIntegerData(95, whichPlayer, null, null, false, setIndex, 0, 0)
endfunction

local integer count = KKApiQueryTaskCurrentProgress(Player(0), id)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'
function KKApiQueryTaskCurrentProgress takes player whichPlayer, integer setIndex returns integer
    return japi.RequestExtraIntegerData(95, whichPlayer, null, null, false, setIndex, 0, 0)
 endfunction

local count = japi.KKApiQueryTaskCurrentProgress(jass.Player(0), id)
```

原文：[kkapi/KKApiQueryTaskCurrentProgress.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiQueryTaskCurrentProgress.md)

---

### 获取玩家任务总进度

获取玩家地图任务总进度，需要先在作者之家创建地图任务并生成任务ID。

##### 参数

| 参数名  | 类型          | 说明                             |
| :--- | :---------- | :----------------------------- |
| 玩家   | player\|玩家  | 判断的玩家                          |
| 任务ID | integer\|整数 | 任务ID，通过作者之家创建任务时，勾选后任务数据获取后生成。 |

##### 返回值

整数

##### 调用示例

![image-KKApiQueryTaskTotalProgress](https://create.kkdzpt.com/kkapidoc/image-KKApiQueryTaskTotalProgress.png)


**WorldEdit Trigger**

**JASS**

```JASS
function KKApiQueryTaskTotalProgress takes player whichPlayer, integer setIndex returns integer
    return RequestExtraIntegerData(96, whichPlayer, null, null, false, setIndex, 0, 0)
endfunction


local integer count = KKApiQueryTaskTotalProgress(Player(0), id)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

function KKApiQueryTaskTotalProgress takes player whichPlayer, integer setIndex returns integer
    return japi.RequestExtraIntegerData(96, whichPlayer, null, null, false, setIndex, 0, 0)
endfunction

local count = japi.KKApiQueryTaskTotalProgress(jass.Player(0), id)
```

原文：[kkapi/KKApiQueryTaskTotalProgress.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiQueryTaskTotalProgress.md)

---

### 获取玩家地图成就点数

获取玩家地图成就点数

##### 参数

| 参数名 | 类型         | 说明 |
| :-- | :--------- | :- |
| 玩家  | player\|玩家 | 玩家 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image-KKApiAchievementPoints](https://create.kkdzpt.com/kkapidoc/image-KKApiAchievementPoints.png)

**JASS**

```JASS
function KKApiAchievementPoints takes player whichPlayer returns integer
    return RequestExtraIntegerData(99, whichPlayer, null, null, false, 0, 0, 0)
endfunction

local integer count = KKApiAchievementPoints(Player(0))
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

function KKApiAchievementPoints takes player whichPlayer returns integer
        return japi.RequestExtraIntegerData(99, whichPlayer, null, null, false, 0, 0, 0)
endfunction

local integer = japi.KKApiAchievementPoints(jass.Player(0))

```

原文：[kkapi/KKApiAchievementPoints.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiAchievementPoints.md)

---

### 获取玩家地图成就完成状态

获取玩家地图成就完成状态，true=完成，false=未完成

##### 参数

| 参数名  | 类型          | 说明           |
| :--- | :---------- | :----------- |
| 玩家   | player\|玩家  | 玩家           |
| 成就ID | string\|字符串 | 开发者平台对应的成就ID |

##### 返回值

布尔值

##### 调用示例

**WorldEdit Trigger**

![image-KKApiIsAchievementCompleted](https://create.kkdzpt.com/kkapidoc/image-KKApiIsAchievementCompleted.png)

**JASS**

```JASS
function KKApiIsAchievementCompleted takes player whichPlayer, string id returns boolean
    return RequestExtraBooleanData(98, whichPlayer, id, null, false, 0, 0, 0)
endfunction

local boolean a = KKApiIsAchievementCompleted(Player(0), "id"）
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

function KKApiIsAchievementCompleted takes player whichPlayer, string id returns boolean
    return japi.RequestExtraBooleanData(98, whichPlayer, id, null, false, 0, 0, 0)
endfunction

local boolean = japi.KKApiIsAchievementCompleted(jass.Player(0), "id"）

```

原文：[kkapi/KKApiIsAchievementCompleted.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiIsAchievementCompleted.md)

---

## 游戏内数据上报

> 开发者可以将游戏局内的数据或游戏结果结果上报给平台，平台提供相应的数据分析或将数据展示支持。

原文：[menu_kkapi_ingame_datareport.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_ingame_datareport.md)

---

### 上报房间内显示的数据

开发者可以将游戏内的关键数值或结果上报给平台，用于在平台游戏房间内展示以方便玩家相互快速了解实力，数据上报后需在[KK开发者平台](https://create.reckfeng.com)进行配置后才能展示出来。

比如：比如获得MVP次数、最高通关难度等。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 栏位键，用于[KK开发者平台](https://create.reckfeng.com)进行配置 |
| value       | string \| 字符串 | 栏位值，最终展示在房间内数值 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_Stat_SetStat](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_Stat_SetStat.png)

**JASS**

```JASS
native DzAPI_Map_Stat_SetStat takes player whichPlayer, string key, string value returns nothing

call DzAPI_Map_Stat_SetStat( Player(0), "mvpcount", "300" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzAPI_Map_Stat_SetStat( jass.Player(0), "mvpcount", "300" ) 
```

原文：[kkapi/DzAPI_Map_Stat_SetStat.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Stat_SetStat.md)

---

### 上报埋点数据

可以在游戏内的关键行为操作进行埋点，以便进行游戏内的玩家行为数据统计分析（比如某个英雄选择次数），上报前需先在[KK开发者平台](https://create.reckfeng.com)创建埋点。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| eventKey | string \| 字符串 | [KK开发者平台](https://create.reckfeng.com)创建埋点时所填写的Key |
| eventType | string \| 字符串 | 预留参数，保持为空即可 |
| value | integer\|整数 | 事件发生次数 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_Statistics](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_Statistics.png)

**JASS**

```JASS
function DzAPI_Map_Statistics takes player whichPlayer, string eventKey, string eventType, integer value returns nothing
    call RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
endfunction
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_Statistics( whichPlayer,  eventKey,  eventType,  value )
    call japi.RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
end
```

原文：[kkapi/DzAPI_Map_Statistics.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Statistics.md)

---

### 上报本局游戏玩家数据

上报本局游戏的玩家数据，比如战斗力、杀敌数等。

以下数据项Key由平台统一定义，请勿随意自行上传：
* RankIndex: 乱斗模式排名，请参见[上报本局游戏玩家排名](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitPlayerRank.md) 
* InnerGameMode: 地图模式名称，请参见[上报本局游戏地图模式名称](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitGameMode.md) 
* GameResult: 游戏结果（上报后立即结束游戏），请参见[上报本局游戏玩家游戏结果](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitGameResult.md) 
* GameResultNoEnd: 游戏结果（上报后不会立即结束游戏），请参见[上报本局游戏玩家游戏结果(不结束游戏)](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitGameResultNoEnd.md) 

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key | string \| 字符串 | 数据项Key  |
| value | string \| 字符串 | 数据项Value |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GameResult_CommitData](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GameResult_CommitData.png)

**JASS**

```JASS
function DzAPI_Map_GameResult_CommitData takes player whichPlayer, string key, string value returns nothing
	call RequestExtraIntegerData(69, whichPlayer, key, value, false, 0, 0, 0)
endfunction

call DzAPI_Map_GameResult_CommitData(Player(0), "gold", "10000")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GameResult_CommitData( whichPlayer,  eventKey,  eventType,  value )
    japi.RequestExtraBooleanData(69, whichPlayer, eventKey, eventType, false, value, 0, 0)
end

DzAPI_Map_GameResult_CommitData(jass.Player(0), "gold", "10000")
```

原文：[kkapi/DzAPI_Map_GameResult_CommitData.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitData.md)

---

### 上报本局游戏模式

上报本局游戏所选择的游戏模式名称。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ | 
| value | string \| 字符串 |  地图模式名称   |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GameResult_CommitGameMode](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GameResult_CommitGameMode.png) 

**JASS**

```JASS
function DzAPI_Map_GameResult_CommitData takes player whichPlayer, string key, string value returns nothing
	call RequestExtraIntegerData(69, whichPlayer, key, value, false, 0, 0, 0)
endfunction

function DzAPI_Map_GameResult_CommitGameMode takes string value returns nothing
	call DzAPI_Map_GameResult_CommitData(GetLocalPlayer(),"InnerGameMode",value)
	set value=null
endfunction

call DzAPI_Map_GameResult_CommitGameMode("N10")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GameResult_CommitData( whichPlayer,  eventKey,  eventType,  value )
    japi.RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
end

function DzAPI_Map_GameResult_CommitGameMode( value )
	DzAPI_Map_GameResult_CommitData(jass.GetLocalPlayer(),"InnerGameMode",value)
end

DzAPI_Map_GameResult_CommitGameMode("N10")

```

原文：[kkapi/DzAPI_Map_GameResult_CommitGameMode.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitGameMode.md)

---

### 上报本局游戏玩家称号

上报本局游戏玩家所获得的称号，请注意**称号Key**不能和[上报本局游戏玩家数据](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitData.md)的**数据项Key**重复。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    | 
| value | string \| 字符串 | 称号Key |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**
 
![DzAPI_Map_GameResult_CommitTitle](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GameResult_CommitTitle.png)


**JASS**

```JASS
function DzAPI_Map_GameResult_CommitData takes player whichPlayer, string key, string value returns nothing
	call RequestExtraIntegerData(69, whichPlayer, key, value, false, 0, 0, 0)
endfunction

function DzAPI_Map_GameResult_CommitTitle takes player whichPlayer, string value  returns nothing
	call DzAPI_Map_GameResult_CommitData(whichPlayer, value, "1")
	set whichPlayer=null
	set value=null
endfunction 

call DzAPI_Map_GameResult_CommitData(Player(0), "MVP")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GameResult_CommitData( whichPlayer,  eventKey,  eventType,  value )
    japi.RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
end

function DzAPI_Map_GameResult_CommitTitle( whichPlayer,  value  )
	DzAPI_Map_GameResult_CommitData(whichPlayer,value,"1")
end

DzAPI_Map_GameResult_CommitData(jass.Player(0), "MVP")
```

原文：[kkapi/DzAPI_Map_GameResult_CommitTitle.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitTitle.md)

---

### 上报本局游戏玩家排名

对于乱斗模式玩法的地图，上报每一名玩家的名次。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    | 
| value | integer \| 整数 | 玩家名次  |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GameResult_CommitPlayerRank](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GameResult_CommitPlayerRank.png)

**JASS**

```JASS
function DzAPI_Map_GameResult_CommitData takes player whichPlayer, string key, string value returns nothing
	call RequestExtraIntegerData(69, whichPlayer, key, value, false, 0, 0, 0)
endfunction

function DzAPI_Map_GameResult_CommitPlayerRank takes player whichPlayer, integer value returns nothing
	call DzAPI_Map_GameResult_CommitData(whichPlayer,"RankIndex",I2S(value))
	set whichPlayer=null
	set value=0
endfunction

call DzAPI_Map_GameResult_CommitPlayerRank(Player(0), 1)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GameResult_CommitData( whichPlayer,  eventKey,  eventType,  value )
    japi.RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
end

function DzAPI_Map_GameResult_CommitPlayerRank( whichPlayer,  value )
	DzAPI_Map_GameResult_CommitData(whichPlayer,"RankIndex",value)
end

DzAPI_Map_GameResult_CommitPlayerRank(jass.Player(0), 1)
```

原文：[kkapi/DzAPI_Map_GameResult_CommitPlayerRank.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitPlayerRank.md)

---

### 上报本局游戏玩家游戏结果

上报本局游戏玩家游戏结果（胜负），提交后会立即结束游戏。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| value | integer \| 整数 | 1=胜利，0=失败 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GameResult_CommitGameResult](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GameResult_CommitGameResult.png)

**JASS**

```JASS
function DzAPI_Map_GameResult_CommitData takes player whichPlayer, string key, string value returns nothing
	call RequestExtraIntegerData(69, whichPlayer, key, value, false, 0, 0, 0)
endfunction
 
function DzAPI_Map_GameResult_CommitGameResult takes player whichPlayer, integer value returns nothing
	call DzAPI_Map_GameResult_CommitData(whichPlayer,"GameResult",I2S(value))
	set whichPlayer=null
endfunction

call DzAPI_Map_GameResult_CommitGameResultNoEnd(Player(0), 1)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GameResult_CommitData( whichPlayer,  eventKey,  eventType,  value )
    japi.RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
end

function DzAPI_Map_GameResult_CommitGameResult( whichPlayer,  value )
	DzAPI_Map_GameResult_CommitData(whichPlayer,"GameResult",value)
end

DzAPI_Map_GameResult_CommitGameResultNoEnd(jass.Player(0), 1)
```

原文：[kkapi/DzAPI_Map_GameResult_CommitGameResult.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitGameResult.md)

---

### 上报本局游戏玩家游戏结果(不结束游戏)

上报本局游戏玩家游戏结果（胜负），提交后不会立即结束游戏，适用于游戏通关后还有奖励关的地图。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| value | integer \| 整数 | 1=胜利，0=失败  |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**
 
![image-DzAPI_Map_GameResult_CommitGameResultNoEnd](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GameResult_CommitGameResultNoEnd.png)

**JASS**

```JASS
function DzAPI_Map_GameResult_CommitData takes player whichPlayer, string key, string value returns nothing
	call RequestExtraIntegerData(69, whichPlayer, key, value, false, 0, 0, 0)
endfunction

function DzAPI_Map_GameResult_CommitGameResultNoEnd takes player whichPlayer, integer value returns nothing
	call DzAPI_Map_GameResult_CommitData(whichPlayer,"GameResultNoEnd",I2S(value))
	set whichPlayer=null
endfunction

call DzAPI_Map_GameResult_CommitGameResultNoEnd(Player(0), 1)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GameResult_CommitData( whichPlayer,  eventKey,  eventType,  value )
    japi.RequestExtraBooleanData(34, whichPlayer, eventKey, eventType, false, value, 0, 0)
end

function DzAPI_Map_GameResult_CommitGameResultNoEnd( whichPlayer,  value )
	DzAPI_Map_GameResult_CommitData(whichPlayer,"GameResultNoEnd",value)
end

DzAPI_Map_GameResult_CommitGameResultNoEnd(jass.Player(0), 1)
```

原文：[kkapi/DzAPI_Map_GameResult_CommitGameResultNoEnd.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GameResult_CommitGameResultNoEnd.md)

---

## 轻量级服务端模块

> 平台提供一系列通用的服务器逻辑计算模块，地图可以利用这些能力实现一些轻量级的网游功能。

原文：[menu_kkapi_light_servercompute.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_light_servercompute.md)

---

### 玩家在地图自定义排行榜上的排名

获取玩家在指定自定义排行榜上的排名。

需要先在[KK开发者平台](https://create.reckfeng.com)创建自定义排行榜后才能使用，自定义存档排行榜基于服务器存档排序得出。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| id | integer\|整数 | [KK开发者平台](https://create.reckfeng.com)所配置的自定义排行榜Key值 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 玩家在该排行榜上的排名，如果名次大于100，则返回0 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_CustomRank.png](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_CustomRank.png)

**JASS**

```JASS
function DzAPI_Map_CustomRank takes player whichPlayer, integer id returns integer
    return RequestExtraIntegerData(52, whichPlayer, null, null, false, id, 0, 0)
endfunction

call DzAPI_Map_CustomRank(Player(0), 1)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_CustomRank( whichPlayer,  id )
    return japi.RequestExtraIntegerData(52, whichPlayer, nil, nil, false, id, 0, 0)
end

DzAPI_Map_CustomRank(jass.Player(0), 1)
```

原文：[kkapi/DzAPI_Map_CustomRank.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_CustomRank.md)

---

### 触发BOSS击杀

告知平台服务器游戏内发生了BOSS击杀，请求平台服务器计算BOSS掉落内容。

触发之后可通过[BOSS击杀后的掉落内容](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerArchiveDrop)和[BOSS击杀后的掉落数量](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerArchiveEquip)具体掉落内容

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| bosskey  | string \| 字符串 | 被击杀的BOSS标识，即[KK开发者平台](https://create.reckfeng.com)预先配置的BossKey |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_OrpgTrigger](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_OrpgTrigger.png)

**JASS**

```JASS
function DzAPI_Map_OrpgTrigger takes player whichPlayer, string bosskey returns nothing
    call RequestExtraIntegerData(28, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_OrpgTrigger(Player(0), "Roshan")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_OrpgTrigger( whichPlayer,  bosskey )
    japi.RequestExtraIntegerData(28, whichPlayer, key, bosskey, false, 0, 0, 0)
end

DzAPI_Map_OrpgTrigger(jass.Player(0), "Roshan")
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1251 | BossKey不存在（尚未在[KK开发者平台](https://create.reckfeng.com)进行配置） |
| 1252 | 地图没有掉落 |
| 1253 | 地图没有掉落 |
| 1254 | 击杀触发达到今日上限 |

原文：[kkapi/DzAPI_Map_OrpgTrigger.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_OrpgTrigger.md)

---

### BOSS击杀后的掉落内容

游戏内调用[触发BOSS击杀](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_OrpgTrigger.md)后，获取本次掉落的内容项。 

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 被击杀的BOSS标识，即[KK开发者平台](https://create.reckfeng.com)预先配置的BossKey |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 掉落内容（在[KK开发者平台](https://create.reckfeng.com)上配置的掉落项Key） |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetServerArchiveDrop](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetServerArchiveDrop.png)

**JASS**

```JASS
native DzAPI_Map_GetServerArchiveDrop takes player whichPlayer, string key returns string

call DzAPI_Map_GetServerArchiveDrop(Player(0), "Roshan")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetServerArchiveDrop( whichPlayer,  key )
    return japi.RequestExtraStringData(27, whichPlayer, key, nil, false, 0, 0, 0)
end

DzAPI_Map_GetServerArchiveDrop(jass.Player(0), "Roshan")
```

原文：[kkapi/DzAPI_Map_GetServerArchiveDrop.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerArchiveDrop.md)

---

### BOSS击杀后的掉落数量

游戏内调用[触发BOSS击杀](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_OrpgTrigger.md)后，获取本次掉落的数量。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key     | string \| 字符串 | 被击杀的BOSS标识，即[KK开发者平台](https://create.reckfeng.com)预先配置的BossKey |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer | 整数 | 掉落数量（在[KK开发者平台](https://create.reckfeng.com)上配置的掉落数量） |


##### 调用示例

**WorldEdit Trigger**
 
![image-DzAPI_Map_GetServerArchiveEquip](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetServerArchiveEquip.png)

**JASS**

```JASS
native DzAPI_Map_GetServerArchiveEquip takes player whichPlayer, string key returns integer

call DzAPI_Map_GetServerArchiveEquip(Player(0), "Roshan")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetServerArchiveEquip( whichPlayer,  key )
    return japi.RequestExtraIntegerData(26, whichPlayer, key, nil, false, 0, 0, 0)
end

DzAPI_Map_GetServerArchiveEquip(jass.Player(0), "Roshan")
```

原文：[kkapi/DzAPI_Map_GetServerArchiveEquip.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetServerArchiveEquip.md)

---

### 保存全局存档

将变量数据存储到平台服务器上的全局存档中，保存时会受到[KK开发者平台](https://create.reckfeng.com)所配置的保存规则限制。

保存成功后本局游戏及同一时间正在进行的其他游戏局内的所有玩家都会收到[全局存档变化事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Global_ChangeMsg.md)的事件广播。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ | 
| key         | string \| 字符串 | 全局存档变量Key |
| value       | string \| 字符串 | 全局存档变量Value |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_Global_StoreString](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_Global_StoreString.png)

**JASS**

```JASS
function DzAPI_Map_Global_StoreString takes string key, string value returns nothing
	call RequestExtraStringData(37, GetLocalPlayer(), key, value, false, 0, 0, 0)
endfunction

call DzAPI_Map_Global_StoreString("RoshanKillCount", "101")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_Global_StoreString( key,  value )
    return japi.RequestExtraStringData(37, GetLocalPlayer(), key, value, false, 0, 0, 0)
end

DzAPI_Map_Global_StoreString("RoshanKillCount", "101")
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 1757 | 超过上传频率 |
| 1758 | Value超过每局最大值 |
| 1761 | Value小于每局最小值 |

原文：[kkapi/DzAPI_Map_Global_StoreString.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Global_StoreString.md)

---

### 读取全局存档

从服务器上读取的全局存档数据。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| key         | string \| 字符串 | 全局存档变量Key | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 服务器上的全局存档变量Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_Global_GetStoreString](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_Global_GetStoreString.png)

**JASS**

```JASS
function DzAPI_Map_Global_GetStoreString takes string key returns string
    return RequestExtraStringData(36, GetLocalPlayer(), key, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_Global_GetStoreString("RoshanKillCount")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_Global_GetStoreString( key )
    return japi.RequestExtraStringData(36, GetLocalPlayer(), key, nil, false, 0, 0, 0)
end

DzAPI_Map_Global_GetStoreString("RoshanKillCount")
```

原文：[kkapi/DzAPI_Map_Global_GetStoreString.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Global_GetStoreString.md)

---

### 全局存档变化事件

本局游戏或同一时间正在进行的其他游戏局修改了全局存档的后都会触发这个回调事件。

请使用[事件响应 - 数据同步事件的数据](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerSyncData.md)来获得发生变化的全局存档变量KEY，使用[读取全局存档](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Global_GetStoreString.md)获取最新的全局存档变量Value。

##### 参数

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_Global_ChangeMsg](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_Global_ChangeMsg.png)

**JASS**

```JASS
function DzAPI_Map_Global_ChangeMsg takes trigger trig returns nothing
	call DzTriggerRegisterSyncData(trig, "DZGAU", true)
endfunction 
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_Global_ChangeMsg(trig)
	japi.DzTriggerRegisterSyncData( trig, "DZGAU", true ) 
end
```

原文：[kkapi/DzAPI_Map_Global_ChangeMsg.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Global_ChangeMsg.md)

---

### 自定义排行榜上榜人数

获取指定自定义排行榜的上榜人数。

##### 访问授权限制

高级接口，需要授权后才允许使用。

##### 参数
| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ | 
| id | integer \| 整数 | [KK开发者平台](https://create.reckfeng.com)所配置的自定义排行榜Key值 |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 上榜人数，最大值为100。 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_CustomRankCount](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_CustomRankCount.png)

**JASS** 

```JASS
function DzAPI_Map_CustomRankCount takes integer id returns integer
	return RequestExtraIntegerData(78, null, null, null, false, id, 0, 0)
endfunction

call DzAPI_Map_CustomRankCount(1)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_CustomRankCount( id )
    return japi.RequestExtraIntegerData(78, nil, nil, nil, false, id, 0, 0)
end

DzAPI_Map_CustomRankCount(1)
```

原文：[kkapi/DzAPI_Map_CustomRankCount.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_CustomRankCount.md)

---

### 自定义排行榜上的玩家昵称	

获取指定自定义排行榜上指定名次的玩家昵称。

##### 访问授权限制

高级接口，需要授权后才允许使用。

##### 参数
| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ | 
| id | integer \| 整数 | [KK开发者平台](https://create.reckfeng.com)所配置的自定义排行榜Key值 |
| ranking | integer \| 整数 | 名次 |


##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 玩家昵称 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_CustomRankPlayerName](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_CustomRankPlayerName.png)

**JASS** 

```JASS
function DzAPI_Map_CustomRankPlayerName takes integer id, integer ranking returns string
    return RequestExtraStringData(79, null, null, null, false, id, ranking, 0)
endfunction

// 获取1号自定义排行榜第5名玩家的昵称
call DzAPI_Map_CustomRankPlayerName(1, 5)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_CustomRankPlayerName( id, ranking )
    return japi.RequestExtraStringData(79, nil, nil, nil, false, id, ranking, 0)
end

-- 获取1号自定义排行榜第5名玩家的昵称
DzAPI_Map_CustomRankPlayerName(1, 5)
```

原文：[kkapi/DzAPI_Map_CustomRankPlayerName.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_CustomRankPlayerName.md)

---

### 	自定义排行榜上的玩家数值

获取指定自定义排行榜上指定名次的玩家数值（排行榜值）。

##### 访问授权限制

高级接口，需要授权后才允许使用。

##### 参数
| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ | 
| id | integer \| 整数 | [KK开发者平台](https://create.reckfeng.com)所配置的自定义排行榜Key值 |
| ranking | integer \| 整数 | 名次 |

##### 返回结果
| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 玩家数值（排行榜值） |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_CustomRankValue](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_CustomRankValue.png)

**JASS** 

```JASS
function DzAPI_Map_CustomRankValue takes integer id, integer ranking returns integer
    return RequestExtraIntegerData(80, null, null, null, false, id, ranking, 0)
endfunction

// 获取1号自定义排行榜第5名玩家的排行榜值
call DzAPI_Map_CustomRankValue(1, 5)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_CustomRankValue( id, ranking )
    return japi.RequestExtraIntegerData(80, nil, nil, nil, false, id, ranking, 0)
end

-- 获取1号自定义排行榜第5名玩家的排行榜值
DzAPI_Map_CustomRankValue(1, 5)
```

原文：[kkapi/DzAPI_Map_CustomRankValue.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_CustomRankValue.md)

---

### 随机只读存档-生成随机数

通知服务器端产生一个随机数，并将随机数保存至指定的只读型存档变量Key中。

生成随机数时需要关联一个组ID，该组ID可以在[开发者平台](https://create.reckfeng.com)进行防刷分管理，同组ID下各个Key共享CD和次数。 

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度64位 | 
| groupkey  | string \| 字符串 | 最大长度64，可以在[开发者平台](https://create.reckfeng.com)对组ID进行防刷分管理 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 |  |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiRequestBackendLogic](https://create.kkdzpt.com/kkapidoc/image-KKApiRequestBackendLogic.png)

**JASS**

```JASS
function KKApiRequestBackendLogic takes player whichPlayer, string key, string groupkey returns boolean
  return RequestExtraBooleanData(83, whichPlayer, key, groupkey, false, 0, 0, 0)
 endfunction

call KKApiRequestBackendLogic( Player(0), "Key", "groupkey" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiRequestBackendLogic(whichPlayer,key,groupkey)
  return japi.RequestExtraBooleanData(83, whichPlayer, key, groupkey, false, 0, 0, 0)
 end
KKApiRequestBackendLogic( jass.Player(0), "Key", "groupkey" )
```

##### 错误代码

| 代码 | 错误描述           |
| ---- | :----------------- |
| 10314 | 随机存档组KEY错误 |
| 10315 | 触发次数日上限 |
| 10316 | 触发时间 |
| 10317 | KEY已经存在 |
| 10318 | 随机存档数量达到上限 |
| 10319 | 随机存档长度达到上限 |

原文：[kkapi/KKApiRequestBackendLogic.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiRequestBackendLogic.md)

---

### 随机只读存档-判断随机数是否为空

判断服务器端所生成的随机数是否为空。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度63位，区分大小写 | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | True随机只读存档为空，False 随机只读存档已生成 |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiCheckBackendLogicExists](https://create.kkdzpt.com/kkapidoc/image-KKApiCheckBackendLogicExists.png)

**JASS**

```JASS
function KKApiCheckBackendLogicExists takes player whichPlayer, string key returns boolean
  return RequestExtraBooleanData(84, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call KKApiCheckBackendLogicExists( Player(0), "key" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiCheckBackendLogicExists(whichPlayer,key)
  return japi.RequestExtraBooleanData(84, whichPlayer, key, nil, false, 0, 0, 0)
end

KKApiCheckBackendLogicExists( jass.Player(0), "key" )
```

##### 错误代码

无

原文：[kkapi/KKApiCheckBackendLogicExists.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiCheckBackendLogicExists.md)

---

### 随机只读存档-读取随机数的值

读取服务器端所产生的随机数的值。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度64位，区分大小写 | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 服务器端所产生的随机数值 |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiGetBackendLogicIntResult](https://create.kkdzpt.com/kkapidoc/image-KKApiGetBackendLogicIntResult.png)

**JASS**

```JASS
function KKApiGetBackendLogicIntResult takes player whichPlayer, string key returns integer
  return RequestExtraIntegerData(85, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call KKApiGetBackendLogicIntResult( Player(0), "variablename" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiGetBackendLogicIntResult(whichPlayer, key)
  return japi.RequestExtraIntegerData(85, whichPlayer, key, nil, false, 0, 0, 0)
 end

KKApiGetBackendLogicIntResult( jass.Player(0), "variablename" )
```

##### 错误代码

无

原文：[kkapi/KKApiGetBackendLogicIntResult.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiGetBackendLogicIntResult.md)

---

### 随机只读存档-读取随机数的生成时间

读取服务器端所产生随机数的生成时间。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度64位，区分大小写 | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 时间戳 |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiGetBackendLogicUpdateTime](https://create.kkdzpt.com/kkapidoc/image-KKApiGetBackendLogicUpdateTime.png)

**JASS**

```JASS
function KKApiGetBackendLogicUpdateTime takes player whichPlayer, string key returns integer
  return RequestExtraIntegerData(87, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call KKApiGetBackendLogicUpdate( Player(0), "variablename" )		
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiGetBackendLogicUpdateTime(whichPlayer, key)
  return japi.RequestExtraIntegerData(87, whichPlayer, key, nil, false, 0, 0, 0)
end

KKApiGetBackendLogicUpdate( jass.Player(0), "variablename" )
```

##### 错误代码

无

原文：[kkapi/KKApiGetBackendLogicUpdateTime.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiGetBackendLogicUpdateTime.md)

---

### 随机只读存档-读取随机数的组ID

读取指定的随机只读存档变量Key最后一次是由哪个组ID所生成的。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度64位，区分大小写 | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 随机数的组ID |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiGetBackendLogicGroup](https://create.kkdzpt.com/kkapidoc/image-KKApiGetBackendLogicGroup.png)

**JASS**

```JASS
function KKApiGetBackendLogicGroup takes player whichPlayer, string key returns string
  return RequestExtraStringData(88, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call KKApiGetBackendLogicGroup( Player(0), "key" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiGetBackendLogicGroup(whichPlayer, key)
  return japi.RequestExtraStringData(88, whichPlayer, key, nil, false, 0, 0, 0)
end

KKApiGetBackendLogicGroup( jass.Player(0), "key" )
```

##### 错误代码

无

原文：[kkapi/KKApiGetBackendLogicGroup.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiGetBackendLogicGroup.md)

---

### 随机只读存档-删除随机数

删除指定的随机只读存档变量Key中所保存的随机数。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度63位，区分大小写 | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 |  |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiRemoveBackendLogicResult](https://create.kkdzpt.com/kkapidoc/image-KKApiRemoveBackendLogicResult.png)

**JASS**

```JASS
function KKApiRemoveBackendLogicResult takes player whichPlayer, string key returns boolean
  return RequestExtraBooleanData(89, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call KKApiRemoveBackendLogicResult( Player(0), "key" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiRemoveBackendLogicResult(whichPlayer,key)
  return japi.RequestExtraBooleanData(89, whichPlayer, key, nil, false, 0, 0, 0)
end 

KKApiRemoveBackendLogicResult( jass.Player(0), "variablename" )
```

##### 错误代码

无

原文：[kkapi/KKApiRemoveBackendLogicResult.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiRemoveBackendLogicResult.md)

---

### 获取随机只读存档今日剩余次数

每日05:00点刷新，调用前请先在开发者平台创建组ID



##### 参数

| 参数名      | 类型   | 说明                   |
| :---------- | :----- | :-------------------- |
| whichPlayer | player \| 玩家 | 玩家           |
| 组ID       | integer\| 整数 | 开发者平台填写的组ID     |




##### 返回值
整数

##### 调用示例

**WorldEdit Trigger**

![image-KKApiRandomSaveGameCount](https://create.kkdzpt.com/kkapidoc/image-KKApiRandomSaveGameCount.png)

**JASS**

```JASS
 function KKApiRandomSaveGameCount takes player whichPlayer, string groupkey returns integer
    return RequestExtraIntegerData(101, whichPlayer, groupkey, null, false, 0, 0, 0)
endfunction

local integer count =KKApiRandomSaveGameCount(Player(0), "1")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

 function KKApiRandomSaveGameCount takes player whichPlayer, string groupkey returns integer
    return japi.RequestExtraIntegerData(101, whichPlayer, groupkey, null, false, 0, 0, 0)
endfunction

local integer =japi.KKApiRandomSaveGameCount(jass.Player(0), "1")
```

原文：[kkapi/KKApiRandomSaveGameCount.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiRandomSaveGameCount.md)

---

### 获取服务器存档限制余额

获取指定服务器存档变量的天/周上限余额，需要在[开发者平台](https://create.reckfeng.com)配置服务器存档防刷。

##### 访问授权限制

高级接口，需要授权后才允许使用。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key  | string \| 字符串 | 随机只读存档变量Key，最大长度63位，区分大小写 | 

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 服务器存档可用余额，如存档A上限100，当天使用80返回20 |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiGetServerValueLimitLeft](https://create.kkdzpt.com/kkapidoc/image-KKApiGetServerValueLimitLeft.png)

**JASS**

```JASS
function KKApiGetServerValueLimitLeft takes player whichPlayer, string key returns integer
  return RequestExtraIntegerData(82, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call KKApiGetServerValueLimitLeft( Player(0), "key" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiGetServerValueLimitLeft(whichPlayer, key) 
  return japi.RequestExtraIntegerData(82, whichPlayer, key,nil, false, 0, 0, 0)
end

KKApiGetServerValueLimitLeft( jass.Player(0), "key" )
```

##### 错误代码

无

原文：[kkapi/KKApiGetServerValueLimitLeft.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiGetServerValueLimitLeft.md)

---

## 多地图联动

> 提供多张地图之间的数据互通、相互推广及运营的能力。

原文：[menu_kkapi_crossmap.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_crossmap.md)

---

### 读取服务器存档组

读取当前开发者账号下的服务器存档组变量数据。

##### 访问授权限制

需先前往[KK开发者平台](https://create.reckfeng.com)开通服务器存档组权限，将当前地图被加入至服务器存档组的地图列表后可用。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 存档变量Key |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 服务器存档组上最新的存档变量Value |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_GetPublicArchive](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_GetPublicArchive.png)

**JASS**

```JASS
function DzAPI_Map_GetPublicArchive takes player whichPlayer, string key returns string
    return RequestExtraStringData(32, whichPlayer, key, null, false, 0, 0, 0)
endfunction

call DzAPI_Map_GetPublicArchive(Player(0), "MapA-N10-Completed")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_GetPublicArchive( whichPlayer,  key )
    return japi.RequestExtraStringData(32, whichPlayer, key, nil, false, 0, 0, 0)
end

DzAPI_Map_GetPublicArchive(japi.Player(0), "MapA-N10-Completed")
```

原文：[kkapi/DzAPI_Map_GetPublicArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_GetPublicArchive.md)

---

### 保存服务器存档组

将变量保存到当前开发者账号下的服务器存档组中。

##### 访问授权限制

需先在[KK开发者平台](https://create.reckfeng.com)自行开通服务器存档组权限，且当前地图被加入至服务器存档组的地图列表后可用。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| key         | string \| 字符串 | 存档变量Key |
| value       | string \| 字符串 | 存档变量Value |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_SavePublicArchive](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_SavePublicArchive.png)

**JASS**

```JASS
function DzAPI_Map_SavePublicArchive takes player whichPlayer, string key, string value returns boolean
    return RequestExtraBooleanData(31, whichPlayer, key, value, false, 0, 0, 0)
endfunction

call DzAPI_Map_SavePublicArchive(Player(0), "MapA-N10-Completed", "1")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_SavePublicArchive( whichPlayer,  key,  value )
    return japi.RequestExtraBooleanData(31, whichPlayer, key, value, false, 0, 0, 0)
end
```

原文：[kkapi/DzAPI_Map_SavePublicArchive.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_SavePublicArchive.md)

---

### 玩家在指定地图的地图等级

获取玩家在指定地图的地图等级。

##### 访问授权限制

需先前往[KK开发者平台](https://create.reckfeng.com)将当前地图加入关联地图列表后可用。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| mapId | player \| 玩家   | 玩家    |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 地图等级 |

##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_MapsLevel](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_MapsLevel.png)

**JASS**

```JASS
function DzAPI_Map_MapsLevel takes player whichPlayer, integer mapId returns integer
    return RequestExtraIntegerData(57, whichPlayer, null, null, false, mapId, 0, 0)
endfunction

call DzAPI_Map_MapsLevel(Player(0), 180699)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_MapsLevel( whichPlayer, mapId )
    return RequestExtraIntegerData(57, whichPlayer, nil, nil, false, mapId, 0, 0)
end 

DzAPI_Map_MapsLevel(jass.Player(0), 180699)
```

原文：[kkapi/DzAPI_Map_MapsLevel.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_MapsLevel.md)

---

## KK - JAPI 

###### 特效

原文：[menu_kkapi_japi.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_japi.md)

---

### 绑定特效

绑定特效到对象上，可以给单位/物品绑定

##### 参数

| 参数名 | 类型          | 说明       |
| :-- | :---------- | :------- |
| 对象  | widget \| 对象  | 可以是单位/物品 |
| 绑定点 | string \| 字符串 | 绑定点名称    |
| 特效  | effect \| 特效  | 绑定的特效    |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzBindEffect.png)

**JASS**

```JASS
native DzBindEffect takes widget parent, string attachPoint, effect whichEffect returns nothing

local effect eff = call AddSpecialEffect( "Abilities\\Spells\\Other\\TalkToMe\\TalkToMe.mdl", 100, 0)

call DzBindEffect(GetTriggerUnit(), "origin", eff)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\TalkToMe\\TalkToMe.mdl", 100, 0)
japi.DzBindEffect(jass.GetTriggerUnit(), "origin", eff)
```

原文：[kkjapi/DzBindEffect.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzBindEffect.md)

---

### 解除绑定特效

可以让绑定在单位身上的特效分离出来，被分离的特效能设置坐标、缩放

##### 参数

| 参数名 | 类型         | 说明    |
| :-- | :--------- | :---- |
| 特效  | effect\|特效 | 绑定的特效 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzUnbindEffect.png)

**JASS**

```JASS
native DzUnbindEffect takes effect whichEffect returns nothing

local effect eff = AddSpecialEffect( "Abilities\\Spells\\Other\\TalkToMe\\TalkToMe.mdl", 100, 0)
call DzUnbindEffect(eff)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\TalkToMe\\TalkToMe.mdl", 100, 0)
japi. DzUnbindEffect(eff)
```

原文：[kkjapi/DzUnbindEffect.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzUnbindEffect.md)

---

### 获取特效透明度

获取特效透明度和设置特效透明度配合用

##### 参数

| 参数名    | 类型           | 说明 |
| :----- | :----------- | :- |
| effect | effect \| 特效 | 特效 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetEffectVertexAlpha.png)

**JASS**

```JASS
native DzGetEffectVertexAlpha takes effect whichEffect returns integer

local integer alpha = DzGetEffectVertexAlpha()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local alpha = japi.DzGetEffectVertexAlpha()
```

原文：[kkjapi/DzGetEffectVertexAlpha.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetEffectVertexAlpha.md)

---

### 设置特效透明度

设置特效透明度，0=不显示，255=显示

##### 参数

| 参数名 | 类型          | 说明    |
| :-- | :---------- | :---- |
| 特效  | effect\|特效  | 设置的特效 |
| 透明度 | integer\|整数 | 透明度   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSetEffectVertexAlpha.png)

**JASS**

```JASS
native DzSetEffectVertexAlpha takes effect whichEffect, integer alpha returns nothing

local effect eff = AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 0, 0))
call DzSetEffectVertexAlpha(eff, 0)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 0, 0))
japi.DzSetEffectVertexAlpha(eff, 0)
```

原文：[kkjapi/DzSetEffectVertexAlpha.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetEffectVertexAlpha.md)

---

### 获取特效颜色

获取特效颜色和设置特效颜色配合用

##### 参数

| 参数名    | 类型           | 说明 |
| :----- | :----------- | :- |
| effect | effect \| 特效 | 特效 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetEffectVertexColor.png)

**JASS**

```JASS
native DzGetEffectVertexColor takes effect whichEffect returns integer

local integer color = DzGetEffectVertexColor()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local color = japi.DzGetEffectVertexColor()
```

原文：[kkjapi/DzGetEffectVertexColor.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetEffectVertexColor.md)

---

### 设置特效颜色

设置特效颜色，透明无效

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 特效	   | effect\|特效  | 设置的特效 |
| color | integer\|整数 | 颜色    |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSetEffectVertexColor.png)

**JASS**

```JASS
native DzSetEffectVertexColor takes effect whichEffect, integer color returns nothing

local effect eff = call AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 0, 0))
call DzSetEffectVertexColor(eff, DzGetColor( 255, 255, 255, 255))
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 0, 0))
japi.DzSetEffectVertexColor(eff, japi.DzGetColor( 255, 255, 255, 255))
```

原文：[kkjapi/DzSetEffectVertexColor.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetEffectVertexColor.md)

---

### 设置特效坐标

设置特效x,y,z坐标，立即移动。修复了ydjapi里特效超出出生范围一定距离后游戏不会渲染的问题了

##### 参数

| 参数名 | 类型         | 说明    |
| :-- | :--------- | :---- |
| 特效  | effect\|特效 | 设置的特效 |
| x   | real\|实数   | x坐标   |
| y   | real\|实数   | y坐标   |
| z   | real\|实数   | z坐标   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSetEffectPos.png)

**JASS**

```JASS
native DzSetEffectPos takes effect whichEffect, real x, real y, real z returns nothing

local effecf eff = AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 100, 0)
call DzSetEffectPos(eff, 0, 0, 0)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 100, 0)
japi.DzSetEffectPos(eff, 0, 0, 0)
```

原文：[kkjapi/DzSetEffectPos.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetEffectPos.md)

---

### 特效缩放

用来缩放特效

##### 参数

| 参数名   | 类型         | 说明    |
| :---- | :--------- | :---- |
| 特效    | effect\|特效 | 设置的特效 |
| scale | real\|实数   | 缩小数值  |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSetEffectScale.png)

**JASS**

```JASS
 native DzSetEffectScale takes effect whichHandle, real scale returns nothing

local effecf eff = AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 100, 0)
call DzSetEffectScale( eff, 1.00)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\ANsa\\ANsaTarget.mdl", 100, 0)
japi.DzSetEffectScale( eff, 1.00)
```

原文：[kkjapi/DzSetEffectScale.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetEffectScale.md)

---

### 设置特效播放（编号）动画

按照动画编号播放特效动画

##### 参数

| 参数名 | 类型          | 说明   |
| :-- | :---------- | :--- |
| 特效  | effect\|特效  | 特效   |
| 编号  | integer\|整数 | 动画编号 |
| 方式  | integer\|整数 | 播放方式 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSetEffectAnimation.png)

**JASS**

```JASS
native DzSetEffectAnimation takes effect whichEffect, integer index, integer flag returns nothing

call DzSetEffectAnimation(eff, 1, 1)
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzSetEffectAnimation(eff, 1, 1)
```

原文：[kkjapi/DzSetEffectAnimation.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetEffectAnimation.md)

---

### 设置特效播放（动作名）动画

按照动作名名播放特效动画

##### 参数

| 参数名 | 类型          | 说明                   |
| :-- | :---------- | :------------------- |
| 特效  | effect\|特效  | 特效                   |
| 动作名 | string\|字符串 | 动画名称                 |
| 链接名 | string\|字符串 | 变身动画才需要链接名，填“”空字符串就行 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzPlayEffectAnimation.png)

**JASS**

```JASS
native DzPlayEffectAnimation takes effect whichEffect, string anim, string link returns nothing

local effect eff = AddSpecialEffect( "Abilities\\Spells\\Other\\TalkToMe\\TalkToMe.mdl", 100, 0)
call DzPlayEffectAnimation(eff, "death", "")
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local eff = jass.AddSpecialEffect( "Abilities\\Spells\\Other\\TalkToMe\\TalkToMe.mdl", 100, 0)
japi.DzPlayEffectAnimation(eff, "death", "")
```

原文：[kkjapi/DzPlayEffectAnimation.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzPlayEffectAnimation.md)

---

### 转换屏幕坐标到世界x坐标

转化世界坐标为屏幕深度

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzConvertScreenPositionX.png)

**JASS**

```JASS
native DzConvertScreenPositionX takes real x, real y returns real

local real count = DzConvertScreenPositionX( 0, 0 )
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzConvertScreenPositionX( 0, 0 )
```

原文：[kkjapi/DzConvertScreenPositionX.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzConvertScreenPositionX.md)

---

### 转换屏幕坐标到世界y坐标

转化世界坐标为屏幕深度

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzConvertScreenPositionY.png)

**JASS**

```JASS
native DzConvertScreenPositionY takes real x, real y returns real

local real count = DzConvertScreenPositionY( 0, 0 )
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzConvertScreenPositionY( 0, 0 )
```

原文：[kkjapi/DzConvertScreenPositionY.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzConvertScreenPositionY.md)

---

### 转换世界坐标为屏幕深度\[同步\]

转化世界坐标为屏幕深度

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |
| z   | real \| 实数 | z坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzConvertWorldPositionDepth.png)

**JASS**

```JASS
native DzConvertWorldPositionDepth takes real x, real y, real z returns real

local real count = DzConvertWorldPositionDepth( 0, 0, 0)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzConvertWorldPositionDepth( 0, 0, 0)
```

原文：[kkjapi/DzConvertWorldPositionDepth.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzConvertWorldPositionDepth.md)

---

### 转换世界坐标为屏幕x坐标\[同步\]

转化世界坐标为屏幕x坐标

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |
| z   | real \| 实数 | z坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzConvertWorldPositionX.png)

**JASS**

```JASS
 native DzConvertWorldPositionX takes real x, real y, real z returns real

local real count = DzConvertWorldPositionX( 0, 0, 0)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzConvertWorldPositionX( 0, 0, 0)
```

原文：[kkjapi/DzConvertWorldPositionX.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzConvertWorldPositionX.md)

---

### 转换世界坐标为屏幕y坐标\[同步\]

转化世界坐标为屏幕y坐标

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |
| z   | real \| 实数 | z坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzConvertWorldPositionY.png)

**JASS**

```JASS
native DzConvertWorldPositionY takes real x, real y, real z returns real

local real count = DzConvertWorldPositionY( 0, 0, 0)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzConvertWorldPositionY( 0, 0, 0)
```

原文：[kkjapi/DzConvertWorldPositionY.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzConvertWorldPositionY.md)

---

### 转换地图坐标为小地图x坐标

转化地图坐标为小地图X坐标，小地图左下角为（0,0）

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameWorldToMinimapPosX.png)

**JASS**

```JASS
native DzFrameWorldToMinimapPosX takes real x, real y returns real

local real count = DzFrameWorldToMinimapPosX(1.00,1.00)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzFrameWorldToMinimapPosX(1.00,1.00)
```

原文：[kkjapi/DzFrameWorldToMinimapPosX.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameWorldToMinimapPosX.md)

---

### 转换地图坐标为小地图y坐标

转化地图坐标为小地图y坐标，小地图左下角为（0,0）

##### 参数

| 参数名 | 类型         | 说明  |
| :-- | :--------- | :-- |
| x   | real \| 实数 | x坐标 |
| y   | real \| 实数 | y坐标 |

##### 返回值

实数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameWorldToMinimapPosY.png)

**JASS**

```JASS
native DzFrameWorldToMinimapPosY takes real x, real y returns real

local real count = DzFrameWorldToMinimapPosY(1.00,1.00)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzFrameWorldToMinimapPosY(1.00,1.00)
```

原文：[kkjapi/DzFrameWorldToMinimapPosY.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameWorldToMinimapPosY.md)

---

### 自定义指定单位的小地图图标

图标大小只支持16\*16，设置图标之前需要打开指定单位的小地图图标显示

##### 参数

| 参数名 | 类型          | 说明               |
| :-- | :---------- | :--------------- |
| 单位  | unit\|单位    | 设置的单位            |
| 图标  | string\|字符串 | true=打开，flase=关闭 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzWidgetSetMinimapIcon.png)

**JASS**

```JASS
native DzWidgetSetMinimapIcon takes unit whichunit, string path returns nothing
 
local unit mouse = CreateUnit( Player(0), 'hfoo', 0, 0, 0))
call DzWidgetSetMinimapIconEnable(mouse, true)
call UnitSetUsesAltIconBJ( true, mouse )
call DzWidgetSetMinimapIcon( mouse, "UI\\Minimap\\MiniMap-Tower.blp")
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'hfoo', 0, 0, 0))
japi.DzWidgetSetMinimapIconEnable(mouse, true)
japi.UnitSetUsesAltIconBJ( true, mouse )

japi.DzWidgetSetMinimapIcon( mouse, "UI\\Minimap\\MiniMap-Tower.blp")
```

原文：[kkjapi/DzWidgetSetMinimapIcon.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzWidgetSetMinimapIcon.md)

---

### 打开/关闭自定义单位的小地图图标

打开关闭自定义单位的小地图图标，配合自定义指定单位的小地图图标使用

##### 参数

| 参数名 | 类型           | 说明               |
| :-- | :----------- | :--------------- |
| 单位  | unit\|单位     | 设置的单位            |
| 布尔值 | boolean\|布尔值 | true=打开，flase=关闭 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzWidgetSetMinimapIconEnable.png)

**JASS**

```JASS
native DzWidgetSetMinimapIconEnable takes unit whichunit, boolean enable returns nothing  
 
local unit mouse = CreateUnit( Player(0), 'hfoo', 0, 0, 0))
call DzWidgetSetMinimapIconEnable( mouse, true)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'hfoo', 0, 0, 0))
japi.DzWidgetSetMinimapIconEnable( null, true)
```

原文：[kkjapi/DzWidgetSetMinimapIconEnable.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzWidgetSetMinimapIconEnable.md)

---

### 获取框选控件

获取鼠标当前框选单位头像控件

##### 参数

| 参数名 | 类型            | 说明 |
| :-- | :------------ | :- |
| 编号  | integer \| 整数 | 编号 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetInfoPanelSelectButton.png)

**JASS**

```JASS
native DzFrameGetInfoPanelSelectButton takes integer index returns integer

local integer fra = DzFrameGetInfoPanelSelectButton(1)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local fra = japi.DzFrameGetInfoPanelSelectButton(1)
```

原文：[kkjapi/DzFrameGetInfoPanelSelectButton.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetInfoPanelSelectButton.md)

---

### 获取农民控件

获取农民控件地址

##### 参数

无



##### 值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetPeonBar.png)

**JASS**

```JASS
native DzFrameGetPeonBar takes nothing returns integer

local integer A = DzFrameGetPeonBar()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local enable = japi.DzFrameGetPeonBar()
```

原文：[kkjapi/DzFrameGetPeonBar.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetPeonBar.md)

---

### 获取聊天窗是否打开

获取当前玩家聊天窗是否打开，异步获取

##### 参数

无



##### 返回值

布尔值

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzIsChatBoxOpen.png)

**JASS**

```JASS
native DzIsChatBoxOpen takes nothing returns boolean

local boolean enable = DzIsChatBoxOpen()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local enable = japi.DzIsChatBoxOpen()
```

原文：[kkjapi/DzIsChatBoxOpen.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzIsChatBoxOpen.md)

---

### 设置单位的鼠标指向ui和血条显示/隐藏

隐藏鼠标指向物品/单位时显示的血条和UI

##### 参数

| 参数名 | 类型           | 说明               |
| :-- | :----------- | :--------------- |
| 单位  | unit\|单位     | 单位               |
| 布尔值 | boolean\|布尔值 | true=显示，false=隐藏 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitPreselectUIVisible.png)

**JASS**

```JASS
native DzSetUnitPreselectUIVisible takes unit whichUnit, boolean visible returns nothing

call DzSetUnitPreselectUIVisible(GetTriggerUnit(), true)
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = japi.DzSetUnitPreselectUIVisible(jass.GetTriggerUnit(), true)
```

原文：[kkjapi/DzSetUnitPreselectUIVisible.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitPreselectUIVisible.md)

---

### 获取子控件

获取指定Frame的子控件

##### 参数

| 参数名   | 类型            | 说明   |
| :---- | :------------ | :--- |
| Frame | integer \| 整数 | 控件地址 |
| ID    | integer \| 整数 | 编号   |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetChild.png)

**JASS**

```JASS
native DzFrameGetChild takes integer frame, integer index returns integer

local integer child = DzFrameGetChild(frame, 0)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local child = japi.DzFrameGetChild(frame, 0)
```

原文：[kkjapi/DzFrameGetChild.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetChild.md)

---

### 获取子控件数量

获取指定Frame的子控件数量

##### 参数

| 参数名   | 类型            | 说明   |
| :---- | :------------ | :--- |
| Frame | integer \| 整数 | 控件地址 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetChildrenCount.png)

**JASS**

```JASS
native DzFrameGetChildrenCount takes integer frame returns integer  

local integer A = DzFrameGetChildrenCount(frame)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local enable = japi.DzFrameGetChildrenCount(frame)
```

原文：[kkjapi/DzFrameGetChildrenCount.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetChildrenCount.md)

---

### 获取技能自动施法指示器

获取技能自动施法指示器，控件类型为sprite frame

##### 参数

| 参数名   | 类型            | 说明   |
| :---- | :------------ | :--- |
| Frame | integer \| 整数 | 控件地址 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetCommandBarButtonAutoCastIndicator.png)

**JASS**

```JASS
native DzFrameGetCommandBarButtonAutoCastIndicator takes integer frame returns integer

local integer count = DzFrameGetCommandBarButtonAutoCastIndicator(frame)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzFrameGetCommandBarButtonAutoCastIndicator(frame)
```

原文：[kkjapi/DzFrameGetCommandBarButtonAutoCastIndicator.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetCommandBarButtonAutoCastIndicator.md)

---

### 获取技能冷却指示器

获取技能冷却指示器，控件类型为sprite frame

##### 参数

| 参数名   | 类型            | 说明   |
| :---- | :------------ | :--- |
| Frame | integer \| 整数 | 控件地址 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetCommandBarButtonCooldownIndicator.png)

**JASS**

```JASS
native DzFrameGetCommandBarButtonCooldownIndicator takes integer frame returns integer

local integer count = DzFrameGetCommandBarButtonCooldownIndicator(frame)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzFrameGetCommandBarButtonCooldownIndicator(frame)
```

原文：[kkjapi/DzFrameGetCommandBarButtonCooldownIndicator.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetCommandBarButtonCooldownIndicator.md)

---

### 获取技能右下角数字文本框体

获取技能右下角数字文本框体

##### 参数

| 参数名   | 类型            | 说明   |
| :---- | :------------ | :--- |
| Frame | integer \| 整数 | 控件地址 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetCommandBarButtonNumberOverlay.png)

**JASS**

```JASS
native DzFrameGetCommandBarButtonNumberOverlay takes integer frame returns integer

local integer count = DzFrameGetCommandBarButtonNumberOverlay(frame)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzFrameGetCommandBarButtonNumberOverlay(frame)
```

原文：[kkjapi/DzFrameGetCommandBarButtonNumberOverlay.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetCommandBarButtonNumberOverlay.md)

---

### 获取技能右下角数字文本控件

获取技能右下角数字文本控件

##### 参数

| 参数名   | 类型            | 说明   |
| :---- | :------------ | :--- |
| Frame | integer \| 整数 | 控件地址 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetCommandBarButtonNumberText.png)

**JASS**

```JASS
native DzFrameGetCommandBarButtonNumberText takes integer frame returns integer

local integer count = DzFrameGetCommandBarButtonNumberText(frame)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzFrameGetCommandBarButtonNumberText(frame)
```

原文：[kkjapi/DzFrameGetCommandBarButtonNumberText.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetCommandBarButtonNumberText.md)

---

### 获取BUFF控件

获取BUFF控件地址

##### 参数

| 参数名 | 类型            | 说明 |
| :-- | :------------ | :- |
| 编号  | integer \| 整数 | 编号 |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetInfoPanelBuffButton.png)

**JASS**

```JASS
native DzFrameGetInfoPanelBuffButton takes integer index returns integer

local integer A = DzFrameGetInfoPanelBuffButton(1)
```

**LUA**

```LUA
local japi = require 'jass.japi'

local enable = japi.DzFrameGetInfoPanelBuffButton(1)
```

原文：[kkjapi/DzFrameGetInfoPanelBuffButton.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetInfoPanelBuffButton.md)

---

### 设置控件视口

设置控件视口后，子控件在边缘超出部分不会显示

##### 参数

| 参数名    | 类型          | 说明               |
| :----- | :---------- | :--------------- |
| frame  | integer\|整数 | 控件地址             |
| boolen | boolen\|布尔值 | true=打开，flase=关闭 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameSetClip.png)

**JASS**

```JASS
native DzFrameSetClip takes integer frame, boolean enable returns nothing


call DzFrameSetClip( frame, true)
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzFrameSetClip( frame, true)
```

原文：[kkjapi/DzFrameSetClip.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameSetClip.md)

---

### 游戏提示信息界面

配合设置游戏提示信息界面一起用

##### 参数

无

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzFrameGetWorldFrameMessage.png)

**JASS**

```JASS
native DzFrameGetWorldFrameMessage takes nothing returns integer

local integer i = DzFrameGetWorldFrameMessage()
```

**LUA**

```LUA
local japi = require "jass.japi"

local i = japi.DzFrameGetWorldFrameMessage()
```

原文：[kkjapi/DzFrameGetWorldFrameMessage.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzFrameGetWorldFrameMessage.md)

---

### 显示游戏提示信息

显示游戏提示信息，如建造完成，技能没有目标等

##### 参数

| 参数名   | 类型           | 说明     |
| :---- | :----------- | :----- |
| frame | integer\|整数  | 消息界面   |
| 消息    | string\|字符串  | 消息内容   |
| color | integer\|整数  | 颜色     |
| 时间    | real\|实数     | 时间     |
| 永久显示  | boolean\|布尔值 | 是否永久显示 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSimpleMessageFrameAddMessage.png)

**JASS**

```JASS
native DzSimpleMessageFrameAddMessage takes integer frame, string text, integer color, real duration, boolean permanent returns nothing

call DzSimpleMessageFrameAddMessage( DzFrameGetWorldFrameMessage(), "11", DzGetColor( 255, 255, 255, 255), 1.00, false)
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzSimpleMessageFrameAddMessage( japi.DzFrameGetWorldFrameMessage(), "11", japi.DzGetColor( 255, 255, 255, 255), 1.00, false)
```

原文：[kkjapi/DzSimpleMessageFrameAddMessage.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSimpleMessageFrameAddMessage.md)

---

### 清理游戏提示信息

配合显示游戏信息一起用

##### 参数

| 参数名   | 类型          | 说明      |
| :---- | :---------- | :------ |
| Frame | integer\|整数 | 需要清理的界面 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzSimpleMessageFrameClear.png)

**JASS**

```JASS
native DzSimpleMessageFrameClear takes integer frame returns nothing
 
call DzSimpleMessageFrameClear( DzFrameGetWorldFrameMessage())
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzSimpleMessageFrameClear( japi.DzFrameGetWorldFrameMessage())
```

原文：[kkjapi/DzSimpleMessageFrameClear.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSimpleMessageFrameClear.md)

---

### 获取商店目标

获取指定商店选中指定玩家的哪个单位

##### 参数

| 参数名         | 类型         | 说明                |
| :---------- | :--------- | :---------------- |
| unit        | Unit\|单位   | 商店单位拥有出售物品选择英雄的单位 |
| whichplayer | Player\|玩家 | 玩家                |

##### 返回值

单位

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetActivePatron.png)

**JASS**

```JASS
native DzGetActivePatron takes unit store, player p returns unit

local integer unit = DzGetActivePatron( unit, Player(1))
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local unit = japi.DzGetActivePatron( unit, jass.Player(1))
print('你的' ..jass.GetUnitName(u).. '被商店'.. unit..'选中了')
```

原文：[kkjapi/DzGetActivePatron.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetActivePatron.md)

---

### 获取玩家选中的单位

异步返回玩家选中的单位

##### 参数

| 参数名 | 类型          | 说明 |
| :-- | :---------- | :- |
| ID  | integer\|整数 | 编号 |

##### 返回值

| 返回值 | 说明           |
| :-- | :----------- |
| 单位  | 返回值是异步，请谨慎使用 |

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetLocalSelectUnit.png)

**JASS**

```JASS
native DzGetLocalSelectUnit takes integer index returns unit

local unit mouse = DzGetLocalSelectUnitCount()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local unit = japi.DzGetLocalSelectUnit(1)
```

原文：[kkjapi/DzGetLocalSelectUnit.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetLocalSelectUnit.md)

---

### 获取玩家选中的单位数量

获取玩家选中的单位数量，返回整数

##### 参数

无

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetLocalSelectUnitCount.png)

**JASS**

```JASS
native DzGetLocalSelectUnitCount takes nothing returns integer 

local integer count = DzGetLocalSelectUnitCount()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzGetLocalSelectUnitCount()
```

原文：[kkjapi/DzGetLocalSelectUnitCount.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetLocalSelectUnitCount.md)

---

### 获取当前选择的单位

获取当前预览窗口显示的单位

##### 参数

无



##### 返回值

unit | 单位

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetSelectedLeaderUnit.png)

**JASS**

```JASS
native DzGetSelectedLeaderUnit takes nothing returns unit

local unit u = DzGetSelectedLeaderUnit()
```

**LUA**

```LUA

local japi = require "jass.japi"
local handle = japi.DzGetSelectedLeaderUnit()
```

原文：[kkjapi/DzGetSelectedLeaderUnit.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetSelectedLeaderUnit.md)

---

### 单位缩放

可以用来缩放单位

##### 参数

| 参数名   | 类型        | 说明   |
| :---- | :-------- | :--- |
| 单位	   | unit \| 单位  | 设置单位 |
| scale | real \| 实数 | 缩放比例 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-](https://create.kkdzpt.com/kkapidoc/image-DzSetWidgetSpriteScale.png)

**JASS**

```JASS
native DzSetWidgetSpriteScale takes widget whichUnit, real scale returns nothing

call DzSetWidgetSpriteScale( unit, 1.00 )
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzSetWidgetSpriteScale( unit, 1.00 )
```

原文：[kkjapi/DzSetWidgetSpriteScale.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetWidgetSpriteScale.md)

---

### 获取字符串数量

获取字符串数量

##### 参数

无

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetJassStringTableCount.png)

**JASS**

```JASS
native DzGetJassStringTableCount takes nothing returns integer

local integer count = DzGetJassStringTableCount()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local count = japi.DzGetJassStringTableCount()
```

原文：[kkjapi/DzGetJassStringTableCount.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetJassStringTableCount.md)

---

### 清除所有模型内存缓存

清空所有模型文件缓存

##### 参数

无

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzModelRemoveAllFromCache.png)

**JASS**

```JASS
native DzModelRemoveAllFromCache takes nothing returns nothing

call DzModelRemoveAllFromCache()
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzModelRemoveAllFromCache()
```

原文：[kkjapi/DzModelRemoveAllFromCache.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzModelRemoveAllFromCache.md)

---

### 清除模型内存缓存

用来清空魔兽的模型文件缓存

##### 参数

| 参数名 | 类型          | 说明    |
| :-- | :---------- | :---- |
| 模型  | string\|字符串 | 模型字符串 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzModelRemoveFromCache.png)

**JASS**

```JASS
native DzModelRemoveFromCache takes string path returns nothing

call DzModelRemoveFromCache( "units\\human\\Arthas\\Arthas.mdl")
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzModelRemoveFromCache( "units\\human\\Arthas\\Arthas.mdl")
```

原文：[kkjapi/DzModelRemoveFromCache.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzModelRemoveFromCache.md)

---

### 设置单位名字

用于修改指定单位的名字

##### 参数

| 参数名 | 类型            | 说明    |
| :-- | :------------ | :---- |
| 单位  | unit\|单位      | 设置的单位 |
| 名称  | string\|字符串		 | 设置的名称 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitName](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitName.png)

**JASS**

```JASS
native DzSetUnitName takes unit whichUnit, string name returns nothing

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitName( mouse, "耗子大魔王" )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitName( mouse, "耗子大魔王" )
```

原文：[kkjapi/DzSetUnitName.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitName.md)

---

### 设置单位描述

用于修改指定单位的描述

##### 参数

| 参数名 | 类型            | 说明    |
| :-- | :------------ | :---- |
| 单位  | unit\|单位      | 设置的单位 |
| 描述  | string\|字符串		 | 设置的描述 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**


![image-DzSetUnitDescription](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitDescription.png)

**JASS**

```JASS
native DzSetUnitDescription takes unit whichUnit, string value returns nothing

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitDescription( mouse, "耗子大魔王" )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitDescription( mouse, "耗子大魔王" )
```

原文：[kkjapi/DzSetUnitDescription.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitDescription.md)

---

### 设置单位头像模型

用于修改指定单位的头像模型，预设英雄模型直接作为头像模型会显示异常，需找到对应的大头像地址进行绑定。

##### 参数

| 参数名    | 类型            | 说明      |
| :----- | :------------ | :------ |
| 单位     | unit\|单位      | 设置的单位   |
| 头像模型地址 | string\|字符串		 | 设置的头像地址 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitPortrait](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitPortrait.png)

**JASS**

```JASS
native DzSetUnitPortrait takes unit whichUnit, string modelFile returns nothing

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitPortrait( mouse, "Objects\\InventoryItems\\NightElfCaptureFlag\\NightElfCaptureFlag.mdl" )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitPortrait( mouse, "Objects\\InventoryItems\\NightElfCaptureFlag\\NightElfCaptureFlag.mdl" )
```

原文：[kkjapi/DzSetUnitPortrait.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitPortrait.md)

---

### 设置英雄称谓

用于修改指定英雄的称谓

##### 参数

| 参数名  | 类型            | 说明    |
| :--- | :------------ | :---- |
| 单位   | unit\|单位      | 设置的单位 |
| 英雄称谓 | string\|字符串		 | 设置的称谓 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitProperName](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitProperName.png)

**JASS**

```JASS
native DzSetUnitProperName takes unit whichUnit, string name returns nothing

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitProperName( mouse, "耗子大魔王" )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitProperName( mouse, "耗子大魔王" )
```

原文：[kkjapi/DzSetUnitProperName.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitProperName.md)

---

### 复活单位

可以复活单位/英雄

##### 参数

| 参数名 | 类型           | 说明      |
| :-- | :----------- | :------ |
| 单位  | unit\|单位     | 设置的单位   |
| 玩家	 | player\|玩家		 | 玩家      |
| hp  | real\|实数     | 生命值     |
| mp  | real\|实数     | 魔法值     |
| 坐标x | real\|实数     | 被复活在坐标x |
| 坐标y | real\|实数     | 被复活在坐标y |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzReviveUnit](https://create.kkdzpt.com/kkapidoc/image-DzReviveUnit.png)

**JASS**

```JASS
native DzReviveUnit takes unit whichUnit, player whichPlayer, real hp, real mp, real x, real y returns nothing

local unit mouse = CreateUnit( Player(0), 'hfoo', 0, 0, 0))
call KillUnit( mouse)
call DzReviveUnit( mouse, Player(0), 1.00, 1.00, 0.00, 0.00 )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'hfoo', 0, 0, 0))
jass.KillUnit( mouse)
japi.DzReviveUnit( mouse, Player(0), 1.00, 1.00, 0.00, 0.00 )
```

原文：[kkjapi/DzReviveUnit.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzReviveUnit.md)

---

### 设置单位普攻弹道速度

设置单位普攻弹道速度

##### 参数

| 参数名 | 类型       | 说明    |
| :-- | :------- | :---- |
| 单位  | unit\|单位 | 设置的单位 |
| 速度  | real\|实数 | 弹道速度  |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitMissileSpeed](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitMissileSpeed.png)

**JASS**

```JASS
native DzSetUnitMissileSpeed takes unit whichUnit, real speed returns nothing

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitMissileSpeed( mouse, 1.00 )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitMissileSpeed( mouse, 1.00 )
```

原文：[kkjapi/DzSetUnitMissileSpeed.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitMissileSpeed.md)

---

### 设置单位普攻弹道模型

用于修改指定单位的普攻弹道模型

##### 参数

| 参数名    | 类型            | 说明     |
| :----- | :------------ | :----- |
| 单位     | unit\|单位      | 设置的单位  |
| 普攻弹道地址 | string\|字符串		 | 普攻弹道地址 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitMissileModel](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitMissileModel.png)

**JASS**

```JASS
native DzSetUnitMissileModel takes unit whichUnit, string modelFile returns nothing

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitMissileModel( mouse, "Abilities\\Weapons\\RedDragonBreath\\RedDragonMissile.mdl" )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitMissileModel( mouse, "Abilities\\Weapons\\RedDragonBreath\\RedDragonMissile.mdl" )
```

原文：[kkjapi/DzSetUnitMissileModel.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitMissileModel.md)

---

### 设置单位普攻弹道弧度

设置单位普攻弹道弧度

##### 参数

| 参数名 | 类型        | 说明    |
| :-- | :-------- | :---- |
| 单位  | unit\|单位  | 设置的单位 |
| 弧度	 | real\|实数	 | 弹道弧度  |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitMissileArc](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitMissileArc.png)

**JASS**

```JASS
native DzSetUnitMissileArc takes unit whichUnit, real arc returns nothing


local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitMissileArc( mouse, 1.00 )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitMissileArc( mouse, 1.00 )
```

原文：[kkjapi/DzSetUnitMissileArc.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitMissileArc.md)

---

### 设置单位普攻弹道自导允许

设置单位普攻弹道自导允许，true=开，false=关

##### 参数

| 参数名 | 类型           | 说明             |
| :-- | :----------- | :------------- |
| 单位  | unit\|单位     | 设置的单位          |
| 开关  | boolean\|布尔值 | true=开，false=关 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSetUnitMissileHoming](https://create.kkdzpt.com/kkapidoc/image-DzSetUnitMissileHoming.png)
**JASS**

```JASS
native DzSetUnitMissileHoming takes unit whichUnit, boolean enable returns nothing


local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzSetUnitMissileHoming( mouse, true )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzSetUnitMissileHoming( mouse, true )
```

原文：[kkjapi/DzSetUnitMissileHoming.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzSetUnitMissileHoming.md)

---

### 结束普攻技能CD

立刻重置普攻技能CD，可以搭配[获取普攻技能](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetAttackAbility.md) 一起使用

##### 参数

| 参数名 | 类型          | 说明      |
| :-- | :---------- | :------ |
| 技能  | ability\|技能 | 重置CD的技能 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzAttackAbilityEndCooldown](https://create.kkdzpt.com/kkapidoc/image-DzAttackAbilityEndCooldown.png)

**JASS**

```JASS
native DzAttackAbilityEndCooldown takes ability whichHandle returns nothing
native DzGetAttackAbility takes unit whichUnit returns ability

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzAttackAbilityEndCooldown( japi.DzGetAttackAbility(mouse) )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzAttackAbilityEndCooldown( japi.DzGetAttackAbility(mouse) )
```

原文：[kkjapi/DzAttackAbilityEndCooldown.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzAttackAbilityEndCooldown.md)

---

### 获取普攻技能

获取指定单位的普攻技能，可以搭配[结束普攻技能CD](https://create.kkdzpt.com/kkapidoc/kkjapi/DzAttackAbilityEndCooldown.md) 一起使用

##### 参数

| 参数名 | 类型       | 说明        |
| :-- | :------- | :-------- |
| 单位  | unit\|单位 | 获取普攻技能的单位 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzGetAttackAbility](https://create.kkdzpt.com/kkapidoc/image-DzGetAttackAbility.png)

**JASS**

```JASS
native DzAttackAbilityEndCooldown takes ability whichHandle returns nothing
native DzGetAttackAbility takes unit whichUnit returns ability

local unit mouse = CreateUnit( Player(0), 'Hpal', 0, 0, 0))
call DzAttackAbilityEndCooldown( japi.DzGetAttackAbility(mouse) )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local mouse = jass.CreateUnit( jass.Player(0), 'Hpal', 0, 0, 0))
japi.DzAttackAbilityEndCooldown( japi.DzGetAttackAbility(mouse) )
```

原文：[kkjapi/DzGetAttackAbility.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzGetAttackAbility.md)

---

### 新建地形装饰物

新建地形装饰物在指定坐标

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 样式    | integer\|整数 | 样式    |
| 坐标x   | real\|实数    | 坐标x   |
| 坐标y   | real\|实数    | 坐标y   |
| 坐标z   | real\|实数    | 坐标z   |
| 角度    | real\|实数    | 角度    |
| 缩放比例  | real\|实数    | 缩放比例  |

##### 返回值

整数

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadCreate](https://create.kkdzpt.com/kkapidoc/image-DzDoodadCreate.png)

**JASS**

```JASS
function DzDoodadCreate takes integer id, integer var, real x, real y, real z, real rotate, real scale returns integer

call DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
```

**LUA**

```LUA
local japi = require 'jass.japi'
local jass = require 'jass.common'

local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
```

原文：[kkjapi/DzDoodadCreate.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadCreate.md)

---

### 设置装饰物模型

设置装饰物模型

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 模型地址  | string\|字符串 | 坐标y   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetModel](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetModel.png)

**JASS**

```JASS
function DzDoodadSetModel takes integer doodad, string modelFile returns nothing

call DzDoodadSetModel( doddad, "Doodads\\Ashenvale\\Props\\SentinelStatue\\SentinelStatue.mdl" )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetModel( doddad, "Doodads\\Ashenvale\\Props\\SentinelStatue\\SentinelStatue.mdl" )
```

原文：[kkjapi/DzDoodadSetModel.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetModel.md)

---

### 装饰物播放动画

让指定装饰物播放动画

##### 参数

| 参数名    | 类型            | 说明                     |
| :----- | :------------ | :--------------------- |
| 装饰物id  | integer\|整数   | 地形装饰物                  |
| 动作名	   | string\|字符串   | 动作名称                   |
| 随机播放		 | boolean\|布尔值	 | true=随机播放，false=关闭随机播放 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetAnimation](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetAnimation.png)

**JASS**

```JASS
function DzDoodadSetAnimation takes integer doodad, string animName, boolean animRandom returns nothing

call DzDoodadSetAnimation( doodad, "death", true )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetAnimation( Doodad, "death", true )
```

原文：[kkjapi/DzDoodadSetAnimation.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetAnimation.md)

---

### 设置装饰物位置

设置装饰物位置到坐标xyz

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 坐标x   | real\|实数    | 坐标x   |
| 坐标y   | real\|实数    | 坐标y   |
| 坐标z   | real\|实数    | 坐标z   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetPosition](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetPosition.png)

**JASS**

```JASS
function DzDoodadSetPosition takes integer doodad, real x, real y, real z returns nothing

call DzDoodadSetPosition( doddad, 0, 0, 0 )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetPosition( doddad, 0, 0, 0 )
```

原文：[kkjapi/DzDoodadSetPosition.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetPosition.md)

---

### 设置装饰物颜色

设置装饰物颜色

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物ID | integer\|整数 | 地形装饰物 |
| 色值    | integer\|整数 | 色值    |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetColor](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetColor.png)

**JASS**

```JASS
function DzDoodadSetColor takes integer doodad, integer color returns nothing

call DzDoodadSetColor( Doodad, DzGetColor(255, 255, 255, 255) )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetColor( Doodad, japi.DzGetColor(255, 255, 255, 255) )
```

原文：[kkjapi/DzDoodadSetColor.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetColor.md)

---

### 装饰物显示/隐藏

让指定装饰物显示/隐藏

##### 参数

| 参数名   | 类型          | 说明               |
| :---- | :---------- | :--------------- |
| 装饰物id | integer\|整数 | 地形装饰物            |
| 布尔值   | boolean\|实数 | true=显示，false=隐藏 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetVisible](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetVisible.png)

**JASS**

```JASS
function DzDoodadSetVisible takes integer doodad, boolean enable returns nothing

call DzDoodadSetVisible( doodad, false )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetVisible( doodad, false )
```

原文：[kkjapi/DzDoodadSetVisible.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetVisible.md)

---

### 设置装饰物动画播放速度

设置指定装饰物播放速度

##### 参数

| 参数名   | 类型          | 说明     |
| :---- | :---------- | :----- |
| 装饰物id | integer\|整数 | 地形装饰物  |
| 播放速度  | real\|实数		  | 动画播放速度 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetTimeScale](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetTimeScale.png)

**JASS**

```JASS
native DzDoodadSetTimeScale takes integer doodad, real scale returns nothing

call DzDoodadSetTimeScale( doodad, 1.5 )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetTimeScale( Doodad, 1.5 )
```

原文：[kkjapi/DzDoodadSetTimeScale.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetTimeScale.md)

---

### 改变装饰物队伍颜色

改变装饰物队伍颜色

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 颜色    | integer\|整数 | 颜色    |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetTeamColor](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetTeamColor.png)

**JASS**

```JASS
function DzDoodadSetTeamColor takes integer doodad, integer color returns nothing

call DzDoodadSetTeamColor( Doodad, Color00 )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetTeamColor( Doodad, Color00 )
```

原文：[kkjapi/DzDoodadSetTeamColor.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetTeamColor.md)

---

### 修改装饰物尺寸

设置装饰物缩放尺寸xyz

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 坐标x   | real\|实数    | 坐标x   |
| 坐标y   | real\|实数    | 坐标y   |
| 坐标z   | real\|实数    | 坐标z   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetOrientMatrixScale](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetOrientMatrixScale.png)

**JASS**

```JASS
function DzDoodadSetOrientMatrixScale takes integer doodad, real x, real y, real z returns nothing

call DzDoodadSetOrientMatrixScale(doodad, 0.5, 0.5, 0.5 )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetOrientMatrixScale(doodad, 0.5, 0.5, 0.5 )
```

原文：[kkjapi/DzDoodadSetOrientMatrixScale.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetOrientMatrixScale.md)

---

### 装饰物重置大小

让指定装饰物重置大小

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 坐标x   | real\|实数    | 坐标x   |
| 坐标y   | real\|实数    | 坐标y   |
| 坐标z   | real\|实数    | 坐标z   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetOrientMatrixResize](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetOrientMatrixResize.png)

**JASS**

```JASS
function DzDoodadSetOrientMatrixResize takes integer doodad returns nothing

call DzDoodadSetOrientMatrixResize( dooodad )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetOrientMatrixScale(doodad, 0.5, 0.5, 0.5 )
japi.DzDoodadSetOrientMatrixResize( doodad )
```

原文：[kkjapi/DzDoodadSetOrientMatrixResize.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetOrientMatrixResize.md)

---

### 设置装饰物旋转

设置装饰物旋转方向到坐标

##### 参数

| 参数名   | 类型          | 说明    |
| :---- | :---------- | :---- |
| 装饰物id | integer\|整数 | 地形装饰物 |
| 角度	   | real\|实数    | 旋转角度  |
| 坐标x   | real\|实数    | 坐标x   |
| 坐标y   | real\|实数    | 坐标y   |
| 坐标z   | real\|实数    | 坐标z   |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image-DzDoodadSetOrientMatrixRotate](https://create.kkdzpt.com/kkapidoc/image-DzDoodadSetOrientMatrixRotate.png)

**JASS**

```JASS
function DzDoodadSetOrientMatrixRotate takes integer doodad, real angle, real axisX, real axisY, real axisZ returns nothing

call DzDoodadSetOrientMatrixRotate( doodad, 0, 0, 0, 0 )
```

**LUA**

```LUA
local japi = require 'jass.japi'


local Doodad = japi.DzDoodadCreate( 'AOgs', 0, 0, 0, 0, 20.00, 1 )
japi.DzDoodadSetOrientMatrixRotate( doodad, 0, 0, 0, 0 )
```

原文：[kkjapi/DzDoodadSetOrientMatrixRotate.md](https://create.kkdzpt.com/kkapidoc/kkjapi/DzDoodadSetOrientMatrixRotate.md)

---

## 其他

###### 数据同步：

原文：[menu_kkapi_other.md](https://create.kkdzpt.com/kkapidoc/menu_kkapi_other.md)

---

### 同步数据

向本局游戏的其他玩家发送数据同步广播，用以防止游戏内各玩家的数据不一致导致的掉线。

其他玩家可通过[同步数据事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterSyncData.md)接收广播内容。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| prefix         | string \| 字符串 | 事件标识。“DZ”开头的事件名称为平台统一定义，请勿随意使用 |
| data       | string \| 字符串 | 发送给本局游戏其他玩家的数据内容 |

##### 返回结果

无

##### 调用示例

**WorldEdit Trigger**

![image-DzSyncData](https://create.kkdzpt.com/kkapidoc/image-DzSyncData.png)

**JASS**

```JASS
native DzSyncData takes string prefix, string data returns nothing

call DzSyncData("Boss", "HP=1000")
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzSyncData("Boss", "HP=1000")
```

原文：[kkapi/DzSyncData.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzSyncData.md)

---

### 数据同步事件

接收到来自平台、或本局游戏其他玩家所发送[同步数据](https://create.kkdzpt.com/kkapidoc/kkapi/DzSyncData.md)的回调事件。

可通过[事件响应 - 数据同步事件的来源玩家](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerSyncPlayer.md)和[事件响应 - 数据同步事件的数据](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerSyncData.md)获取事件响应数据。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| prefix  | string \| 字符串 | 事件标识 |
| server  | boolean \| 布尔值 | 事件来源，True 表示来自平台，False 表示来自游戏局内 |

##### 调用示例

**WorldEdit Trigger**

![image-DzTriggerRegisterSyncData](https://create.kkdzpt.com/kkapidoc/image-DzTriggerRegisterSyncData.png)

**JASS**

```JASS
native DzTriggerRegisterSyncData takes trigger trig, string prefix, boolean server returns nothing

function trigActions takes nothing return nothing
	// Write Your Code Here
endfunction 

local trigger trig = CreateTrigger()
call TriggerAddAction(trig, function trigActions)
call DzTriggerRegisterSyncData(trig, "gold", false)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

local trig = jass.CreateTrigger()

jass.TriggerAddAction(trig, function()
	-- Write Your Code Here
end)

japi.DzTriggerRegisterSyncData(trig, "gold", false) 
```

原文：[kkapi/DzTriggerRegisterSyncData.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterSyncData.md)

---

### 事件响应 - 数据同步事件的来源玩家

获取是哪位玩家发送了数据同步事件。

仅限在[数据同步事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterSyncData.md)内使用。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| player \| 玩家 | 发送数据同步事件的来源玩家 |

##### 调用示例

**WorldEdit Trigger**

![image-DzGetTriggerSyncPlayer](https://create.kkdzpt.com/kkapidoc/image-DzGetTriggerSyncPlayer.png)

**JASS**

```JASS
native DzGetTriggerSyncPlayer takes nothing returns player

call DzGetTriggerSyncPlayer()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi" 

japi.DzGetTriggerSyncPlayer()
```

原文：[kkapi/DzGetTriggerSyncPlayer.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerSyncPlayer.md)

---

### 事件响应 - 数据同步事件的数据

获取数据同步事件中所收到的数据内容。

仅限在[数据同步事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzTriggerRegisterSyncData.md)、[全局存档变化事件](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_Global_ChangeMsg)内使用。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| string \| 字符串 | 收到的数据内容 |

##### 调用示例

**WorldEdit Trigger**

![image-DzGetTriggerSyncData](https://create.kkdzpt.com/kkapidoc/image-DzGetTriggerSyncData.png)

**JASS**

```JASS
native DzGetTriggerSyncData takes nothing returns string 

call DzGetTriggerSyncData()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi" 

japi.DzGetTriggerSyncData()
```

原文：[kkapi/DzGetTriggerSyncData.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetTriggerSyncData.md)

---

### 开启/关闭游戏内辅助功能

地图可以根据自身特点，强制打开或关闭视距调整、显示血条/蓝条、智能施法功能。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| whichPlayer | player \| 玩家   | 玩家    |
| option   | integer \| 整数 | 1=启用视距调整，2=显示血条/蓝条，3=启用智能施法，4=改键 |
| enable | boolean \| 布尔值 | True 为开启，False 为关闭 |

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| boolean \| 布尔值 | 同enable参数 |


##### 调用示例

**WorldEdit Trigger**

![image-DzAPI_Map_EnablePlatformSettings](https://create.kkdzpt.com/kkapidoc/image-DzAPI_Map_EnablePlatformSettings.png)

**JASS**

```JASS
function DzAPI_Map_EnablePlatformSettings takes player whichPlayer, integer option, boolean enable returns boolean
    return RequestExtraBooleanData(43, whichPlayer, null, null, enable, option, 0, 0)
endfunction

call DzAPI_Map_EnablePlatformSettings(Player(0), 1, false)
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function DzAPI_Map_EnablePlatformSettings( whichPlayer,  option, enable )
    return japi.RequestExtraBooleanData(43, whichPlayer, nil, nil, enable, option, 0, 0)
end

DzAPI_Map_EnablePlatformSettings(jass.Player(0), 1, false)
```

原文：[kkapi/DzAPI_Map_EnablePlatformSettings.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzAPI_Map_EnablePlatformSettings.md)

---

### 开启/关闭宽屏模式

地图可以根据自身特点，强制打开或关闭的宽屏优化支持功能。

开启宽屏模式可以解决单位被拉伸显得比较“胖”的问题。

##### 参数

| 参数名      | 类型             | 说明    |
| :---------- | :--------------- | :------ |
| enable | boolean \| 布尔值 | True 启用宽屏支持，False 使用游戏原本的方式 |

##### 返回结果

无


##### 调用示例

**WorldEdit Trigger**

![image-DzEnableWideScreen](https://create.kkdzpt.com/kkapidoc/image-DzEnableWideScreen.png)

**JASS**

```JASS
native DzEnableWideScreen takes boolean enable returns nothing

call DzEnableWideScreen(true)
```

**LUA**

```LUA
local japi = require "jass.japi"

japi.DzEnableWideScreen(true)
```

原文：[kkapi/DzEnableWideScreen.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzEnableWideScreen.md)

---

### 设置魔兽窗口大小

设置魔兽窗口大小，如：修改为1920/1080

##### 参数

| 参数名 | 类型          | 说明   |
| :-- | :---------- | :--- |
| 宽   | integer \| 整数 | 窗口宽度 |
| 高   | integer \| 整数 | 窗口高度 |

##### 返回值

布尔值

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzChangeWindowSize.png)

**JASS**

```JASS
native DzChangeWindowSize takes integer width, integer height returns boolean

call DzChangeWindowSize( 1920, 1080)
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzChangeWindowSize( 1920, 1080)
```

原文：[kkapi/DzChangeWindowSize.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzChangeWindowSize.md)

---

### 获取FPS帧数

异步获取当前玩家帧数

##### 参数

无

##### 返回值

| 返回值 | 说明           |
| :-- | :----------- |
| 整数  | 返回值是异步，请谨慎使用 |

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzGetFPS.png)

**JASS**

```JASS
native DzGetFPS takes nothing returns integer

local integer count = DzGetFPS()
```

**LUA**

```LUA
local japi = require 'jass.japi'

local fps = japi.DzGetFPS()
```

原文：[kkapi/DzGetFPS.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzGetFPS.md)

---

### 设置FPS显示/隐藏

设置FPS是否显示

##### 参数

| 参数名 | 类型           | 说明               |
| :-- | :----------- | :--------------- |
| 布尔值 | boolean\|布尔值 | true=显示，flase=隐藏 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzToggleFPS.png)

**JASS**

```JASS
native DzToggleFPS takes boolean show returns nothing

call DzToggleFPS(true)
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzToggleFPS(true)
```

原文：[kkapi/DzToggleFPS.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzToggleFPS.md)

---

### 解锁BLP像素限制

解锁魔兽高清图片的512像素限制

##### 参数

| 参数名 | 类型           | 说明               |
| :-- | :----------- | :--------------- |
| 布尔值 | boolean\|布尔值 | true=开启，flase=关闭 |

##### 返回值

无

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzUnlockBlpSizeLimit.png)

**JASS**

```JASS
native DzUnlockBlpSizeLimit takes boolean enable returns nothing


call DzUnlockBlpSizeLimit(true)
```

**LUA**

```LUA
local japi = require 'jass.japi'

japi.DzUnlockBlpSizeLimit(true)
```

原文：[kkapi/DzUnlockBlpSizeLimit.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzUnlockBlpSizeLimit.md)

---

### 打开QQ群链接

调用后打开QQ群链接，必须以http\://qm.qq.com开头，每分钟只会触发一次。

##### 参数

| 参数名    | 类型            | 说明                                |
| :----- | :------------ | :-------------------------------- |
| string | string \| 字符串 | 必须以http\://qm.qq.com开头，每分钟只会触发一次。 |

##### 返回值

布尔值

##### 调用示例

**WorldEdit Trigger**

![image.png](https://create.kkdzpt.com/kkapidoc/image-DzOpenQQGroupUrl.png)

**JASS**

```JASS
native DzOpenQQGroupUrl takes string url returns boolean

call DzOpenQQGroupUrl( "url" )
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

japi.DzOpenQQGroupUrl( "url" )
```

原文：[kkapi/DzOpenQQGroupUrl.md](https://create.kkdzpt.com/kkapidoc/kkapi/DzOpenQQGroupUrl.md)

---

### 事件响应 - 注册天梯投降事件

当玩家在天梯投降时触发该事件，用“获取投降队伍ID”来获取

*请用[获取投降队伍ID](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiGetLadderSurrenderTeamId.md)使用。

##### 参数

无

##### 返回结果

| 类型    | 说明                             |
| :------ | :------------------------------- |
| integer \| 整数 | 投降队伍的ID |

##### 调用示例

**WorldEdit Trigger**

![image-KKApiTriggerRegisterLadderSurrender](https://create.kkdzpt.com/kkapidoc/image-KKApiTriggerRegisterLadderSurrender.png)

**JASS**

```JASS
function KKApiTriggerRegisterLadderSurrender takes trigger trig returns nothing
    call DzTriggerRegisterSyncData(trig, "DZSR", true)
endfunction

call KKApiTriggerRegisterLadderSurrender()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi" 

function KKApiTriggerRegisterLadderSurrender(trig)
    japi.DzTriggerRegisterSyncData(trig, "DZSR", true)
end
```

原文：[kkapi/KKApiTriggerRegisterLadderSurrender.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiTriggerRegisterLadderSurrender.md)

---

### 获取天梯投降队伍的ID

用于天梯投降事件，对应编辑器内设置的队伍顺序从0开始。



##### 参数

无


##### 返回值
整数

##### 调用示例

**WorldEdit Trigger**

![image-KKApiGetLadderSurrenderTeamId](https://create.kkdzpt.com/kkapidoc/image-KKApiGetLadderSurrenderTeamId.png)

**JASS**

```JASS
  function KKApiGetLadderSurrenderTeamId takes nothing returns integer
    return S2I(DzGetTriggerSyncData())
 endfunction

local integer count =KKApiGetLadderSurrenderTeamId()
```

**LUA**

```LUA
local jass = require "jass.common"
local japi = require "jass.japi"

function KKApiGetLadderSurrenderTeamId()
    return japi.DzGetTriggerSyncData()
end
```

原文：[kkapi/KKApiGetLadderSurrenderTeamId.md](https://create.kkdzpt.com/kkapidoc/kkapi/KKApiGetLadderSurrenderTeamId.md)

---

