USE [OrBitX]
GO
/****** Object:  StoredProcedure [dbo].[Txn_SMTIssueExeNew]    Script Date: 2018-5-14 8:36:14 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[Txn_SMTIssueExeNew]
@I_Sender nvarchar(50) = '',
@I_ReturnMessage nvarchar(max)='' output,  --返回的信息,支持多语言
@I_ExceptionFieldName nvarchar(100)='' output, --向客户端报告引起冲突的字段
@I_LanguageId char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand varchar(5)='',		--插件命令
@I_OrBitUserId char(12)= '',			--用户ID
@I_OrBitUserName nvarchar(100)= '',	--用户名
@I_ResourceId	char(12)= '',		--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName nvarchar(100)= '',	--资源名
@I_PKId char(12) = '',				--主键
@I_SourcePKId char(12)='',			--执行拷贝时传入的源主键  
@I_ParentPKId char(12)='',			--父级主键
@I_Parameter nvarchar(100)='',		--插件参数	
@LotSN nvarchar(40)=''	,			--前台扫描入的主批号
@IsCheckSpecification bit='true',
@Side					nvarchar(5)=NULL
AS
BEGIN


	
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED  --20180118
	SET XACT_ABORT ON
	
	DECLARE @debug NVARCHAR(50) 
	SET @debug = @LotSN
	DECLARE @if_debug BIT ='false'


   DECLARE  @temp_issueqty DECIMAL(10,4)=0

	DECLARE @time DATETIME
	SET @time = GETDATE()
	
-- add by ybj 20150713
 IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName, ErooeCommad, Duration) values('Txn_SMTIssueExeNew_debug_1', @debug  , DATEDIFF( SECOND, @time, GETDATE() ) )


	IF  ISNULL(@LotSN,'')=''
	BEGIN
	    SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】不存在,请检查! '
		SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		RETURN -1
	
	END
	IF  CHARINDEX('MO',@LotSN,0)!=0     
	BEGIN
	    SET @I_ReturnMessage='ServerMessage:板边条码不能使用该贴片程序！'
		SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		RETURN -1
	
	END
	IF  (SELECT SNType FROM dbo.MOItemLot  WITH(NOLOCK) WHERE LotSN=@LotSN)='sn'
	BEGIN
        SET @I_ReturnMessage='ServerMessage:板边条码不能使用该贴片程序！'
		SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		RETURN -1
	END

	
	DECLARE @pcbtype_4d  NVARCHAR(50)
	DECLARE  @productlot_4d  NVARCHAR(50)
	DECLARE  @productid_4d  CHAR(12)  --工单对应产品iD
	SELECT @pcbtype_4d= MO.PCBType, @productlot_4d=ProductionLot,@productid_4d=mo.ProductId FROM   lot WITH(NOLOCK) INNER JOIN dbo.MO WITH(NOLOCK) ON  lot.MOId=dbo.MO.moid WHERE  lotsn=@LotSN 
	IF  ISNULL(@productlot_4d,'')=''
	BEGIN
	        SET  @I_ReturnMessage='ServerMessage:该条码联板信息为空!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	END	
	DECLARE  @productlotcount_4d  INT
	SELECT  @productlotcount_4d=COUNT(1)  FROM  lot WITH(NOLOCK) WHERE ProductionLot=@productlot_4d
	IF  EXISTS(SELECT  1 FROM yy_4d WITH(NOLOCK) WHERE productid=@productid_4d) AND   @productlotcount_4d>1 
	BEGIN	   
	   DECLARE  @res_4d  INT
	   EXEC @res_4d=dbo.Txn_smttp_yy4d 
	       @I_Sender = N'', -- nvarchar(50)
	       @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
	       @I_ExceptionFieldName = @I_ExceptionFieldName OUTPUT, -- nvarchar(100)
	       @I_LanguageId = @I_LanguageId, -- char(1)
	       @I_PlugInCommand =@I_PlugInCommand, -- varchar(5)
	       @I_OrBitUserId = @I_OrBitUserId, -- char(12)
	       @I_OrBitUserName = @I_OrBitUserName, -- nvarchar(100)
	       @I_ResourceId = @I_ResourceId, -- char(12)
	       @I_ResourceName = @I_ResourceName, -- nvarchar(100)
	       @I_PKId = '', -- char(12)
	       @I_SourcePKId = '', -- char(12)
	       @I_ParentPKId = '', -- char(12)
	       @I_Parameter = N'', -- nvarchar(100)
	       @LotSN = @LotSN, -- nvarchar(40)
	       @IsCheckSpecification = NULL, -- bit
	       @Side = @Side, -- nvarchar(5)
	       @productlotcount = @productlotcount_4d -- int
	    
	    RETURN  @res_4d
	   
	END
		

	
	declare @para nvarchar(max)=''
	set @para ='@I_ResourceName='''+@I_ResourceName+',@I_ResourceId='''+@I_ResourceId+''',@LotSN='''+@LotSN+''',@IsCheckSpecification='''+convert(nchar(2),@IsCheckSpecification)+''',@Side='''+@Side
				

	
	set @IsCheckSpecification=ISNULL(@IsCheckSpecification,'true')
	DECLARE 
	@WaringQty INT=10,--报警数量
	@LotId CHAR(12),
	@ABSide NVARCHAR(20),
	@MOId CHAR(12),
	@MOName NVARCHAR(50),
	@SpecificationId CHAR(12),
	@SpecificationName NVARCHAR(50),
	@WorkflowStepId CHAR(12),
	@ProductionLot NVARCHAR(50),
    @linkSlotNO NVARCHAR(50) ,---link SlotNO
	@PCBType NVARCHAR(20),
	@WorkflowID CHAR(12),
	@MOSMTPath NVARCHAR(10),
	@_SpecificationId1 CHAR(12)='SPE10000004N',--贴片所对应的规程1
	@_SpecificationId2 CHAR(12)='SPE1000000DN',--贴片所对应的规程2
	@IsSMTMountRequired BIT,
	@IsSMTMountItemAll BIT,
	
	@WorkcenterId CHAR(12),
	@WorkcenterName NVARCHAR(50),
	@Workcenter NVARCHAR(50),	--工作中心名 add by haomj 20150618
	@IsLock BIT,
	@DeviceTypeId CHAR(12),
	@DeviceTypeName NVARCHAR(50)
	
	DECLARE @LinkLotNO_table TABLE    --------- add linkSlotNo record qty table  by qinyp 20150218  ---
	(
	   ROW int 
	   ,qty float 
	   ,lotid NVARCHAR(50)
	)
	DECLARE @LinkLotSN TABLE
	(
		LotId CHAR(12),
		LotSN NVARCHAR(50),
		ProductId CHAR(12),
		Qty DECIMAL(18,4),
		ABSide NVARCHAR(20),
		SpecificationId CHAR(12),
		IsLock BIT,
		MOId CHAR(12),
		MOItemId CHAR(12),
		WorkflowId CHAR(12),
		LatestMoveDate DATETIME, 
		WorkflowStepId CHAR(12),
		RowNum INT
	)
	 
	
	DECLARE @StationNo NVARCHAR(50)
	DECLARE @SLotNO NVARCHAR(50)
	DECLARE @SMTProductId CHAR(12)
	DECLARE @SMTProductName NVARCHAR(400)
	DECLARE @IsMust BIT
	DECLARE @BaseQty DECIMAL(18,4)
	DECLARE @sumQty DECIMAL(18,4)
	DECLARE @LotSNCount INT
	DECLARE @CustomerId CHAR(12)
	DECLARE @WOSN NVARCHAR(50)
	DECLARE @IsHuaWeiCustomer BIT
	DECLARE @isHuajiCustomer BIT = 0 ---- add by qianxm on 2014.10.09 for 华技客户限制强制上料
	
	DECLARE @ToWorkflowStepId CHAR(12)
	DECLARE @ToSpeicifcationId CHAR(12)
	DECLARE @ToNextWorkflowStepId CHAR(12)
	DECLARE @IsJITMode BIT=0
	DECLARE @PreviousWorkflowStepId CHAR(12)
	DECLARE @_SMTMount TABLE   --定义料站表
	(
		ProductId CHAR(12),
		ProductName NVARCHAR(400),
		SLotNO NVARCHAR(20),
		
		StationNo NVARCHAR(20),
		BaseQty DECIMAL(18,4),
		IsMust BIT,
		RowNum INT
	)
	
	DECLARE @_StationNoSlot TABLE   --定义机台-槽位 --用来循环扣料
	(
		StationNo NVARCHAR(20),
		SLotNO NVARCHAR(20),
		BaseQty DECIMAL(18,4),
		RowNum INT
	)
	
	DECLARE @_SMTMountLot TABLE --定义上料表
	(
		LotOnSMTId CHAR(12),
		LotId CHAR(12),
		LotSN NVARCHAR(50),
		ProductId CHAR(12),
		Qty DECIMAL(18,4),
		StationNO NVARCHAR(20),
		SLotNO NVARCHAR(20),
		LinkSLotNO NVARCHAR(20),
		IsLock BIT,
		CreateDate DATETIME,
		RowNum INT
	)
	
	DECLARE @i INT
	DECLARE @s INT
	

	BEGIN  --资源校验
		SET @I_ResourceId=NULL
		SELECT @I_ResourceId=ResourceId ,
			   @WorkcenterId=dbo.Resource.WorkcenterId,
			   @WorkcenterName=ISNULL(dbo.Workcenter.ShortName,'N/A'),  ---- Changed WorkcenterName to ShortName by Qianxm on 2015.01.17
			   @Workcenter=ISNULL(dbo.Workcenter.WorkcenterName,'N/A'),	--add by haomj	20150618
			   @DeviceTypeId=dbo.Resource.DeviceTypeId,
			   @DeviceTypeName=ISNULL(dbo.DeviceType.DeviceTypeName,'N/A')
		FROM Resource WITH(NOLOCK)
		LEFT JOIN dbo.Workcenter WITH(NOLOCK) ON dbo.Resource.WorkcenterId = dbo.Workcenter.WorkcenterId
		LEFT JOIN dbo.DeviceType WITH(NOLOCK) ON dbo.Resource.DeviceTypeId=dbo.DeviceType.DeviceTypeId
		WHERE ResourceName=ISNULL(@I_ResourceName,'')
		
		IF @I_ResourceId IS NULL
		 BEGIN
			SET  @I_ReturnMessage='ServerMessage:本地资源名称【'+ISNULL(@I_ResourceName,'N/A')+'】没有在MES系统中注册!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		IF ISNULL(@WorkcenterId,'')=''
		 BEGIN
			SET  @I_ReturnMessage='ServerMessage:本地资源【'+ISNULL(@I_ResourceName,'N/A')+'】在系统中没有指定工作中心!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		IF ISNULL(@DeviceTypeId,'')=''
		 BEGIN
			SET  @I_ReturnMessage='ServerMessage:本地资源【'+ISNULL(@I_ResourceName,'N/A')+'】在系统中没有指定设备分类!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
	END
	

	DECLARE @IntervalotId CHAR(12)
	BEGIN  --批号校验
	    SELECT @LotId=LotId FROM dbo.Lot WITH(NOLOCK) WHERE LotSN=ISNULL(@LotSN,'N/A')

		SELECT @MOId=MO.MOID,
			   @MOName=ISNULL(MO.MOName,'N/A'),
			   @SpecificationId=Lot.SpecificationId,
			   @WorkflowStepId =Lot.WorkflowStepId,
			   @ProductionLot= ISNULL(Lot.ProductionLot,''),
			   @PCBType =MO.PCBType ,
			   @MOSMTPath=MO.MOSMTPath,
			   @WorkflowID=MO.WorkflowId,
			   @SpecificationName=SpecificationRoot.SpecificationName,
			   @ABSide=Lot.ABSide,
			   @IsSMTMountRequired=ISNULL(dbo.Product.IsSMTMountRequired,'false'),
			   @IsSMTMountItemAll=ISNULL(dbo.Product.IsSMTMountItemAll,'false'),
			   @IsLock=ISNULL(Lot.IsLock,'false'),
			   @CustomerId=MO.CustomerId,
			   @WOSN=MO.WOSN,
			   @IsJITMode=IsJITMode
		FROM  dbo.Lot WITH(NOLOCK)
		LEFT JOIN MO WITH(NOLOCK) ON Lot.MOId =MO.MOID
		LEFT JOIN dbo.Product WITH(NOLOCK) ON dbo.MO.ProductId = dbo.Product.ProductId
		LEFT JOIN dbo.Specification WITH(NOLOCK) ON Lot.SpecificationId=dbo.Specification.SpecificationId
		LEFT JOIN dbo.SpecificationRoot WITH(NOLOCK) ON dbo.Specification.SpecificationRootId = dbo.SpecificationRoot.SpecificationRootId
		WHERE dbo.Lot.LotId=@LotId
		
		------------------------------------------钢网时间管控 add by haomj 20150618-------------------------------------------------------

		
		--DECLARE @WashOnLine DATETIME
		--DECLARE @WashOutLine DATETIME
		--DECLARE @InStockDate DATETIME
		--DECLARE @OutStockDate DATETIME

		--SELECT TOP 1 @WashOnLine=washOnline,@WashOutLine=washoutline,@InStockDate=instockdate,@OutStockDate=outstockdate 
		--FROM dbo.SteelMeshInfo WHERE moid=@moid AND workcenter=@workcenter ORDER BY OutStockDate DESC

		--IF @WashOnLine<@WashOutLine AND @WashOnLine<@OutStockDate
		--BEGIN
		--	IF DATEPART(MINUTE,(GETDATE()-@OutStockDate))>'60'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上钢网已使用超过一小时，请在线清洗。'
		--		RETURN -1
		--	END
		--END

		--ELSE IF @WashOnLine>@OutStockDate AND @WashOutLine<@OutStockDate
		--BEGIN 
		--	IF DATEPART(MINUTE,(GETDATE()-@WashOnLine))>'60'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上钢网已使用超过一小时，请在线清洗。'
		--		RETURN -1
		--	END 

		--	IF DATEPART(HOUR ,(GETDATE()-@OutStockDate))>'12'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上的钢网距上次离线清洗已超过12小时，请离线清洗。'
		--	END 
		--END

		--ELSE IF @WashOnLine>@OutStockDate AND @WashOutLine<@OutStockDate 
		--BEGIN
		--	IF DATEPART(MINUTE,(GETDATE()-@WashOnLine))>'60'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上钢网已使用超过一小时，请在线清洗。'
		--		RETURN -1
		--	END 

		--	IF DATEPART(HOUR ,(GETDATE()-@WashOutLine))>'12'
		--	BEGIN 
		--		SET @I_ReturnMessage='ServerMessage: 扣料失败--该线体上的钢网距上次离线清洗已超过12小时，请离线清洗。'
		--	END  
		--END

		--------------------------------------------
		--判断独立模式：尽早判断卡出贴片程序
		DECLARE  @t_side  TABLE(
		  num INT  IDENTITY(1,1),
		  side NVARCHAR(5)
		)
		INSERT  INTO  @t_side
		        (side )
		SELECT  ABSide FROM  dbo.MO_SMTMount  WITH(NOLOCK)
		 INNER  JOIN  dbo.SMTMount  WITH(NOLOCK) ON dbo.MO_SMTMount.SMTMountName = dbo.SMTMount.SMTMountName
		INNER  JOIN  dbo.SMTMountItem WITH(NOLOCK) ON  dbo.SMTMount.SMTMountId=dbo.SMTMountItem.SMTMountId
		WHERE  dbo.MO_SMTMount.MOId=@MOId AND  dbo.SMTMount.Side=@Side
		
		IF  EXISTS(SELECT  1  FROM    @t_side   WHERE CHARINDEX('A',side,0)!=0 OR CHARINDEX('B',side,0)!=0)
		BEGIN
		         SET @I_ReturnMessage='ServerMessage: 该工单对应的料站表存在A或B面,贴片程序应该选择独立模式贴片!'
			
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
		    
		END
		------------------------------------------
		

	   IF ISNULL(@LotId,'')='' 
		BEGIN		    			
			
				SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】不存在,请检查! 当前贴片面为' + ISNULL(@side,'N/A')
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
						
		END
		SET @IntervalotId=@LotId
	   
	   IF @IsLock='true'
		BEGIN
			SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】已被锁定,请检查!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END
		
	   IF @ProductionLot=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】的连板号为空,请检查!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
		
	   IF ISNULL(@MOId,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】没有找到对应的工单信息!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   IF ISNULL(@WorkflowID,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】没有找到对应的工作流信息!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
		--IF ISNULL(@WorkflowID,'')='WKF1000000TM'			--20150508 by qindl 板边上线工作流不能使用该程序  六轴机使用此贴片且工作流为板边上线
	 --   BEGIN
		--	SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】对应的工作流是板边上线工作流，不能使用该程序!'
		--	SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		--	RETURN -1
	 --   END
	   IF ISNULL(@SpecificationId,'')='' OR ISNULL(@WorkflowStepId,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】没有找到对应的当前规程(节点)信息!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   IF @IsCheckSpecification='true' and @SpecificationId <> @_SpecificationId1 AND @SpecificationId <> @_SpecificationId2
		BEGIN
			SET @I_ReturnMessage='ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】目前所在站点为【'+ISNULL(@SpecificationName,'N/A')+'】,本站点无法操作!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END
		
 
	   SELECT @ToWorkflowStepId=ToWorkflowStepId FROM dbo.WorkflowPath  WITH(NOLOCK) WHERE WorkflowStepId=@WorkflowStepId AND IsDefaultWorkflowPath=1
	   IF @ToWorkflowStepId IS NULL
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:站点【'+ISNULL(@SpecificationName,'N/A')+'】未找到下一节点!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   ELSE
	    BEGIN
			SELECT @ToSpeicifcationId=SpecificationId FROM dbo.WorkflowStep  WITH(NOLOCK) WHERE WorkflowStepId=@ToWorkflowStepId
			SELECT @ToNextWorkflowStepId=ToWorkflowStepId FROM dbo.WorkflowPath  WITH(NOLOCK) WHERE WorkflowStepId=@ToWorkflowStepId AND IsDefaultWorkflowPath=1
	    END
	   
   END
   	

    --add 华为任务令校验
    BEGIN
		EXEC dbo.txn_IsHuaWeiCustomer @CustomerId = @CustomerId, -- char(12)
									  @MOID=@MOId,
									  @IsHuaWeiCustomer = @IsHuaWeiCustomer OUTPUT -- bit
		--IF ISNULL(@IsHuaWeiCustomer,'false')='true' AND ISNULL(@WOSN,'')=''
		-- BEGIN
		--	SET @I_ReturnMessage= 'ServerMessage:批号【'+ISNULL(@LotSN,'N/A')+'】对应的工单【'+@MOName+'】是华为工单,请先维护华为工单的任务令(工单信息->标签任务号)!'
		--	SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		--	RETURN -1
		-- END
		
		 ---- add by Qianxm on 2014.10.09 for 华技客户限制强制上料
		SELECT @CustomerId = Customer.CustomerId FROM Product WITH(NOLOCK)
				INNER JOIN dbo.Customer WITH(NOLOCK) ON Customer.CustomerId = Product.CustomerId
				INNER JOIN MO WITH(NOLOCK) ON MO.ProductId = Product.ProductId
				WHERE MO.MOId = @MOId
		IF( @CustomerId = 'CUS1000000J4' OR @CustomerId ='CUS1000000QL' OR @CustomerId ='CUS1000000RJ' )
		BEGIN
		     SET @IsHuajiCustomer = 1
		     SET @IsSMTMountRequired = 1
		     SET @IsSMTMountItemAll = 1
		END
		ELSE
		BEGIN
		     SET @IsHuajiCustomer = 0
		END
    END

	-----------------OSP检测 暂时屏蔽，待培训后开启，邓峰--------------------------------
	--SPE10000004N  SPE1000000DN


		IF  @IsHuaWeiCustomer='true'  OR  @IsHuajiCustomer='true'
		BEGIN
		IF  @SpecificationId='SPE10000004N'
		BEGIN
				IF  DATEDIFF(HOUR,(SELECT  top 1 CreateDate  FROM  dbo.DataChain WITH(NOLOCK) WHERE  LotId=@lotid  AND SpecificationId='SPE10000004L'),GETDATE())>=12
				BEGIN
						IF @moname NOT IN ('MO060217110628','MO060218012232','MO060218012424','MO060218012426','MO060218012644','MO060218012646','MO060218012649','MO060218020120','MO060218020250','MO060218032018','MO060218040404') --增加后面三个工单，郑异20180131--增加MO060218032018宋慧慧
						BEGIN
							IF NOT EXISTS( SELECT 1 FROM  dbo.SMT_BAKEHOUSE_OUT WITH(NOLOCK) WHERE LotId=@lotid  AND SpecificationId='SPE10000004N')
							BEGIN
								SET @I_ReturnMessage='ServerMessage:该连板已拆包上线超过12小时，必须进入烘烤作业'
								RETURN -1
							END
						END
				END
		END



	IF  @SpecificationId='SPE1000000DN'
	BEGIN
	IF  DATEDIFF(HOUR,(SELECT TOP 1 CreateDate  FROM  dbo.DataChain WITH(NOLOCK) WHERE  LotId=@lotid  AND SpecificationId='SPE10000004N' ORDER  BY  CreateDate  DESC ),GETDATE())>=24
			BEGIN
			IF NOT EXISTS( SELECT 1 FROM  dbo.SMT_BAKEHOUSE_OUT WITH(NOLOCK) WHERE LotId=@lotid  AND SpecificationId='SPE1000000DN')
				BEGIN
				IF NOT EXISTS(SELECT 1 FROM dbo.ProductConfig WHERE ProductId=@moid AND ItemName='不管控回流焊超时')--20171124 增加不管控
					BEGIN
					SET @I_ReturnMessage='ServerMessage:该连板已经距离第一次回流焊超过24小时了，必须进入烘烤作业！'
					RETURN -1
				 END
				END
			END
	END
	END
	-----------------OSP检测--------------------------------


	                                            --OR @CustomerId ='CUS1000000QL' 20150707 xiezq取消华为机器的校验
		IF( @CustomerId = 'CUS1000000J4'  AND  @WorkflowID='WKF1000000R8')      --20141125 qindl 添加华技印刷扫描到贴片时间不能超过两小时
		BEGIN
			DECLARE @scantime DATETIME
			IF @SpecificationId=@_SpecificationId1  --贴片1
			BEGIN
				SELECT TOP 1 @scantime=CreateDate  FROM dbo.DataChain  WITH(NOLOCK) WHERE lotid=@lotid AND SpecificationId=@_SpecificationId1 ORDER BY CreateDate DESC
				IF (DATEDIFF(minute,@scantime,GETDATE())>120)  AND @MONAME NOT IN('MO060217101169','MO060217101311','MO060218012232','MO060218012424','MO060218012426','MO060218012644','MO060218012646','MO060218012649','MO060218020120','MO060218020250') --增加后面三个工单，郑异20180131
				BEGIN 
					SET @I_ReturnMessage='ServerMessage:印刷扫描1到贴片1的时间已超过两个小时' 
					RETURN -1
				END 
			END
			IF @SpecificationId=@_SpecificationId2  AND @MONAME NOT IN('MO060217101169','MO060217101311')  --贴片2 
			BEGIN
				SELECT TOP 1 @scantime=CreateDate  FROM dbo.DataChain WITH(NOLOCK) WHERE lotid=@lotid AND SpecificationId=@_SpecificationId2 ORDER BY CreateDate DESC
				IF (DATEDIFF(minute,@scantime,GETDATE())>120) 
				BEGIN 
					SET @I_ReturnMessage='ServerMessage:印刷扫描2到贴片2的时间已超过两个小时' 
					RETURN -1
				END 
			END
		END

		BEGIN
			DECLARE @Return INT
			EXEC @Return= Check_TinolOnLine
				 @I_ExceptionFieldName=@I_ExceptionFieldName OUTPUT,
				 @I_ReturnMessage=@I_ReturnMessage OUTPUT,
				 @Moid=@MOid
	          
			  IF @Return=-1
			   BEGIN
			        set @I_ReturnMessage='ServerMessage:'+ ISNULL(@I_ReturnMessage,'')+'检查锡膏上线不通过!'
					RETURN -1
			   end
		END
	    
	  
    
    BEGIN  --得到连板批号
		
		INSERT INTO @LinkLotSN
		SELECT LotId,LotSN,ProductId,Qty,ABSide,SpecificationId,ISNULL(IsLock,'false') AS IsLock,
			   MOId,MOItemId,WorkflowId,LatestMoveDate,WorkflowStepId,
			   ROW_NUMBER()OVER(ORDER BY ISNULL('',''))AS RowNum
		FROM dbo.Lot WITH(NOLOCK)
		WHERE MOId=@MOId AND ISNULL(ProductionLot,'')=@ProductionLot
		
		IF(SELECT COUNT(1) FROM (
							       SELECT SpecificationId FROM @LinkLotSN GROUP BY SpecificationId
								)A)>1
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:系统错误,连板【'+@ProductionLot+'】的批号不在同一规程,请联系MES管理处!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		 
		IF(SELECT COUNT(1) FROM (
							       SELECT ABSide FROM @LinkLotSN GROUP BY ABSide
								)A)>1
		 BEGIN
			SET @I_ReturnMessage='ServerMessage:系统错误,连板【'+@ProductionLot+'】的批号的A/B面板不一致,系统无法识别,请联系MES管理处!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		 END
		 
		IF exists(select top 1 LotId from @LinkLotSN where ABSide<>@Side) and isnull(@Side,'')<>'' AND @moid<>'MOD100005H5R' --检查当前扣料面是否正确
		BEGIN
			SET @I_ReturnMessage='ServerMessage:系统错误,连板【'+@ProductionLot+'】的批号当前应贴片的面与当前程序的所选的面不一至,请检查!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END 
		 
	   SELECT @ABSide=MIN(ABSide),@LotSNCount=COUNT(1) FROM @LinkLotSN
	   
	   IF ISNULL(@ABSide,'')=''
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:系统错误,连板【'+@ProductionLot+'】的批号的A/B面板为空,系统无法识别,请联系MES管理处!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
	   IF EXISTS(SELECT 1 FROM @LinkLotSN WHERE IsLock='true' )
	    BEGIN
			SET @I_ReturnMessage='ServerMessage:系统错误,连板【'+@ProductionLot+'】已被锁定,请检查!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	    END
    END 
    
   ---钢网管控 
IF @MOId NOT IN('MOD1000065X6','MOD1000065U5') --add by zhougs 2018-04-11 已完成工单，
BEGIN

    IF  @WorkcenterName in ('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10','S11','S12','S13','S14','S15','S16','S17','S18','S19','S20','S21','S22','S23','S24','S25','S26','S27','S28','S34','S35','S36','S37','S38','S39','S40')
    BEGIN
        DECLARE @res INT 
		EXEC @res=[Txn_Steelmesh_issue_4d]  --('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10')
		@I_ReturnMessage=@I_ReturnMessage  OUTPUT ,
		@MOId=@MOId ,  
		@WorkcenterName=@Workcenter,
		@ABSide=@ABSide  
		   
		IF  @res<>0
		BEGIN
			SET @I_ReturnMessage=isnull(@I_ReturnMessage,'')
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END 
    END
	
END


    -------IPQC审核情况检查
	 --IF  @WorkcenterName in ('S05')
  --  BEGIN
  --      --开始校验该工单线体是否有物料没有经过ipqc在使用的
		-- DECLARE  @lotid_needipqc CHAR(12)
		-- SELECT  TOP  1 @lotid_needipqc=lotid FROM  dbo.MZ_IPQC WITH(NOLOCK)
  --       WHERE  MOID=@moid  AND  ShortLine=@workcentername  AND  checkFlag IS NULL
  --       IF  ISNULL(@lotid_needipqc,'')<>''
		-- BEGIN
		--     DECLARE  @lotsn_needipqc NVARCHAR(50)
		--     SELECT  @lotsn_needipqc= lotsn  FROM  lot WITH(NOLOCK) WHERE lotid=@lotid_needipqc
		--     SET @I_ReturnMessage='ServerMessage:该工单线体存在物料['+@lotsn_needipqc+']上料后,未经过IPQC审核使用的情况！'		
		--	 RETURN -1
		-- end
  --  END
	-------IPQC审核情况检查


    ---刮刀管控  add by zhougs20170918 还有问题暂时取消管控
	--解除取消管控 20170918 by zhengyi 
    IF  @WorkcenterName in ('S01','S02','S03','S04','S06')
    BEGIN
        DECLARE @res3 INT 
		DECLARE @massage NVARCHAR(300)=''
		EXEC @res3=[10.2.0.25].OrBitXE.dbo.Txn_SteelmeshGD_issue_4d   --('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10')
		@I_ReturnMessage=@massage  OUTPUT ,
		@MOId=@MOId ,  
		@WorkcenterName=@Workcenter
		   
		IF  @res3<>0
		BEGIN
			SET @I_ReturnMessage=isnull(@massage,'')
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END 
    END
	----25库刮刀、钢网扣数 xiezq 20170531
    IF  @WorkcenterName  IN ('S01','S02','S03','S04','S05','S06','S07','S08','S09','S10','S11','S12','S13','S14','S15','S16','S17','S18','S19','S20','S21','S22','S23','S24','S25','S26','S27','S28','S34','S35','S36','S37','S38','S39','S40')
    BEGIN
		DECLARE @res1 INT 
		DECLARE @TReturnMessage NVARCHAR(500)
		EXEC @res1=[10.2.0.25].OrBitXE.dbo.Txn_LotOnSMTDevicePartsForLot_Domethod 
		@I_ReturnMessage=@TReturnMessage  OUTPUT ,
		@MOId=@MOId ,  
		@WorkcenterName=@Workcenter,
		@ABSide=@ABSide 
		            
		IF  @res1<>0
		BEGIN
			SET @I_ReturnMessage=isnull(@TReturnMessage,'')
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
		END 
    END
   
   
   

    IF @IsSMTMountRequired='true'
     BEGIN  --获取料站表
        DECLARE  @smtmountid_4d  CHAR(12)
       SELECT  @smtmountid_4d=mo_smtmounttemp4d.smtmountid  FROM  dbo.mo_smtmounttemp4d WITH(NOLOCK) INNER JOIN dbo.MO  ON MO.MOName = mo_smtmounttemp4d.moname
       INNER  JOIN  dbo.SMTMount WITH(NOLOCK) ON SMTMount.SMTMountId = mo_smtmounttemp4d.smtmountid 
       WHERE MOId=@MOId AND mo_smtmounttemp4d.WorkCenterID=@WorkcenterId AND Side=@ABSide
       IF ISNULL(@smtmountid_4d,'')<>''
       BEGIN
           INSERT INTO @_SMTMount
		   SELECT  SMTMountItem_temp4d.ProductId,
				   (dbo.ProductRoot.ProductName+(CASE WHEN ISNULL(Product.ProductDescription,'')='' THEN '' ELSE '/'+Product.ProductDescription END)) AS ProductName,
				   SMTMountItem_temp4d.SLotNO,             
				   @WorkcenterName+SMTMountItem_temp4d.StationNo AS StationNo,
				   SMTMountItem_temp4d.BaseQty AS BaseQty,
				   (CASE WHEN @IsHuajiCustomer = 1 OR  @IsHuaWeiCustomer=1 THEN 1 ELSE SMTMountItem_temp4d.IsMust END) AS IsMust,  --ISNULL(SMTMountItem.IsMust,'false') AS IsMust, --- Modified by Qianxm on 2014.10.09 for 华技客户限制强制上料
				   ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
				   FROM  dbo.SMTMountItem_temp4d WITH(NOLOCK)
				   LEFT JOIN dbo.Product WITH(NOLOCK) ON dbo.SMTMountItem_temp4d.ProductId = dbo.Product.ProductId
		           LEFT JOIN dbo.ProductRoot WITH(NOLOCK) ON dbo.Product.ProductRootId = dbo.ProductRoot.ProductRootId
				   WHERE MOId=@MOId AND WorkcenterId=@WorkcenterId AND SMTMountId=@smtmountid_4d  
			IF NOT EXISTS(SELECT 1 FROM @_SMTMount)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单该线该面有维护临时料站表，但临时料站表明细为空，请展开明细！'
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
			END   
			
		   INSERT INTO @_StationNoSlot       
		   SELECT StationNo,
				  SLotNO,
				  MAX(BaseQty),
				  ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
		   FROM @_SMTMount
		   GROUP BY StationNo,SLotNO,BaseQty
		   
		  -- SELECT  *  FROM  @_StationNoSlot
       
       END
       ELSE
       BEGIN
		   INSERT INTO @_SMTMount
		   SELECT  SMTMountItem.ProductId,
				   (dbo.ProductRoot.ProductName+(CASE WHEN ISNULL(Product.ProductDescription,'')='' THEN '' ELSE '/'+Product.ProductDescription END)) AS ProductName,
				   SMTMountItem.SLotNO,
	               
				   @WorkcenterName+SMTMountItem.StationNo AS StationNo,
				   MAX(SMTMountItem.BaseQty) AS BaseQty,
				   (CASE WHEN @IsHuajiCustomer = 1 OR  @IsHuaWeiCustomer=1 THEN 1 ELSE SMTMountItem.IsMust END) AS IsMust,  --huawei huaji
				   ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
		   FROM dbo.MO_SMTMount WITH(NOLOCK)
		   LEFT JOIN dbo.SMTMount WITH(NOLOCK) ON dbo.MO_SMTMount.SMTMountName = dbo.SMTMount.SMTMountName
		   LEFT JOIN dbo.SMTMountItem WITH(NOLOCK) ON dbo.SMTMount.SMTMountId = dbo.SMTMountItem.SMTMountId
		   LEFT JOIN dbo.Product WITH(NOLOCK) ON dbo.SMTMountItem.ProductId = dbo.Product.ProductId
		   LEFT JOIN dbo.ProductRoot WITH(NOLOCK) ON dbo.Product.ProductRootId = dbo.ProductRoot.ProductRootId
		   WHERE dbo.MO_SMTMount.MOId=@MOId AND dbo.SMTMount.DeviceTypeId=@DeviceTypeId AND SMTMount.Side=@ABSide
		   AND BaseQty>0
		   GROUP BY SMTMountItem.ProductId,
					dbo.ProductRoot.ProductName,
					Product.ProductDescription,
					SMTMountItem.SLotNO,
					SMTMountItem.StationNo,
					SMTMountItem.IsMust
		   
		   IF NOT EXISTS(SELECT * FROM @_SMTMount)
			BEGIN
				SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】在设备分类【'+@DeviceTypeName+'】中没有导入料站表('+@ABSide+'面)2!'
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
			END
		  
		   INSERT INTO @_StationNoSlot       
		   SELECT StationNo,
				  SLotNO,
				  BaseQty,
				  ROW_NUMBER()OVER(ORDER BY ISNULL('','')) AS RowNum
		   FROM @_SMTMount
		   GROUP BY StationNo,SLotNO,BaseQty
       
       END
       
        
      
     END


	 ---SMT 飞达检测---------------20171023 dengfeng
	--IF  @WorkcenterName in ('S01','S02')
	--BEGIN
	--		DECLARE  @fdcheck_tb  slot_table
	--		INSERT  INTO @fdcheck_tb
	--		SELECT  *  FROM  @_StationNoSlot
	--		DECLARE @res_fdcheck INT
	--		EXEC @res_fdcheck= [Txn_smt_fdcheck_4d]
	--		@I_ReturnMessage=@I_ReturnMessage  OUTPUT ,
	--		@Slot_table=@fdcheck_tb
	--		IF  @res_fdcheck<>0
	--		BEGIN
	--				SET @I_ReturnMessage=isnull(@I_ReturnMessage,'')
	--				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
	--				RETURN -1
	--		END
	--END	
	---SMT 飞达检测---------------

      
    IF @IsSMTMountRequired='true'
     BEGIN  --获取上料表
		INSERT INTO @_SMTMountLot
		SELECT dbo.LotOnSMT.LotOnSMTId,
			   dbo.LotOnSMT.LotId,
			   Lot.LotSN,
			   lot.ProductId,
			   Lot.Qty,
			   dbo.LotOnSMT.StationNO,
			   dbo.LotOnSMT.SLotNO,
			   dbo.LotOnSMT.LinkSLotNO,
			   ISNULL(IsLock,'false') AS IsLock,
			   LotOnSMT.CreateDate ,
			   ROW_NUMBER()OVER(ORDER BY LotOnSMT.CreateDate ASC) AS RowNum
		FROM dbo.LotOnSMT WITH(NOLOCK)
		LEFT JOIN dbo.Lot WITH(NOLOCK) ON dbo.LotOnSMT.LotId = dbo.Lot.LotId
		WHERE LotOnSMT.MOId=@MOId AND dbo.LotOnSMT.SMTLineNO=@WorkcenterName
		AND Lot.Qty>0
		ORDER BY LotOnSMT.CreateDate ASC
				
		

		IF @IsSMTMountItemAll='true'  AND NOT EXISTS(SELECT * FROM @_SMTMountLot)
	     BEGIN
			SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】在线别【'+@WorkcenterName+'】中没有上料!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	     END	
	    
	    DECLARE @_LotSNTmp NVARCHAR(50)
	    SELECT TOP 1 @_LotSNTmp=LotSN FROM @_SMTMountLot WHERE IsLock='true' AND Qty>0
	    IF @_LotSNTmp IS NOT NULL
	     BEGIN
			SET @I_ReturnMessage='ServerMessage:物料批号【'+@_LotSNTmp+'】已被锁定,请检查!'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			RETURN -1
	     END
	
     END

   
    IF @IsSMTMountRequired='true' AND @moname NOT IN('MO060117090420','MO060117090430','MO060117090435','MO060117090425','MO060117100148','MO060118020291','MO060118030019','MOB060118030048')
     BEGIN  --检查料是否有上齐以及是否够料
     
		IF @IsSMTMountItemAll='true'
		 BEGIN
			SET @StationNo=NULL
			SET @SLotNO=NULL
			SET @BaseQty=NULL
			SET @sumQty=NULL
			
			SELECT @StationNo=A.StationNo,@SLotNO=A.SLotNO,@BaseQty=A.BaseQty,@sumQty=SUM(ISNULL(B.Qty,0))
			FROM @_StationNoSlot A
			LEFT JOIN @_SMTMountLot B ON A.StationNo=B.StationNo AND A.SLotNO=B.SLotNO
			WHERE EXISTS
			(
				SELECT 1 FROM @_SMTMount WHERE StationNo=A.StationNo AND SLotNO=A.SLotNO AND IsMust='true'
			)
			GROUP BY A.StationNo,A.SLotNO,A.BaseQty
			HAVING SUM(ISNULL(B.Qty,0))<A.BaseQty*@LotSNCount
			
 
			IF @StationNo IS NOT NULL AND @SLotNO IS NOT NULL
			 BEGIN
				SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】在机台【'+@StationNo+'】的槽位【'+@SLotNO+'】处的物料数量【'+CONVERT(NVARCHAR(10),ISNULL(@sumQty,0))+'】不足单位用量【'+CONVERT(NVARCHAR(10),ISNULL(@BaseQty,0))+'*'+CONVERT(NVARCHAR(10),@LotSNCount)+'】('+@ABSide+'面)!'
				SELECT  -2 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -2 ---- Modify by Qianxm on 2014.10.14:  return -2 for remark contraint of @IsSMTMountItemAll, and force the speaker work. 
			 END
			   --END 
		 END
    
     
		--DECLARE @_count INT
		--SELECT @s=COUNT(1),@i=1 FROM @_StationNoSlot
		--WHILE @i<=@s 
		-- BEGIN
		--	SELECT @StationNo=StationNo,
		--	       @SLotNO=SLotNO,
		--	       @BaseQty=BaseQty
		--	FROM @_StationNoSlot WHERE RowNum=@i
			
		--	IF EXISTS(SELECT * FROM @_SMTMount WHERE StationNo=@StationNo AND SLotNO=@SLotNO AND IsMust='true')
		--	 BEGIN
		--		SET @IsMust='true'
		--	 END
		--	ELSE
		--	 BEGIN
		--		SET @IsMust='false'
		--	 END
			
		--	SET @sumQty=0
			
		--	--当一个槽位有多种物料时，这些物料互为替代关系
		--	SELECT @sumQty=SUM(Qty)
		--	FROM @_SMTMountLot 
		--	WHERE StationNO=@StationNo
		--	AND SLotNO=@SLotNO
		--	GROUP BY StationNO,SLotNO 
			
		--	IF @IsMust='true' OR @IsSMTMountItemAll='true' 
		--	 BEGIN
		--		IF @sumQty<@BaseQty*@LotSNCount
		--		 BEGIN
		--			SET @I_ReturnMessage='ServerMessage:工单【'+@MOName+'】在机台【'+@StationNo+'】的槽位【'+@SLotNO+'】处的物料数量【'+CONVERT(NVARCHAR(10),@sumQty)+'】不足单位用量【'+CONVERT(NVARCHAR(10),@BaseQty)+'*'+CONVERT(NVARCHAR(10),@LotSNCount)+'】('+@ABSide+'面)!'
		--			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		--			RETURN -1
		--		 END
		--	 END
		--	SET @i=@i+1
		-- END
		
     END
     
      
    declare @returnvalues int
	declare @LotSNList nvarchar(max)
	set @LotSNList=@LotSN
	exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList,  @SP='Txn_SMTIssueExeNew' ,@Status=1 --标注此批SN正在处理 
	if @returnvalues=-1
	begin
		SET @I_ReturnMessage=isnull(@I_ReturnMessage,'')+'(重复提交已忽视)'+@LotSN
		SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
		return -1
	end
    
    DECLARE @bindLotSNRowNum INT=1
    DECLARE @bindLotSN TABLE
    (
		LotSN NVARCHAR(50),
		ProductLotSN NVARCHAR(50),
		Qty DECIMAL(18,4),
		rowNum INT
    )
    
    BEGIN TRY  --扣料
	
		
		DECLARE @AssyDataChainId CHAR(12)
		DECLARE @LotProductId CHAR(12)
		DECLARE @LotQty DECIMAL(18,4)
		
		DECLARE @i1 INT
		DECLARE @i2 INT
		DECLARE @s1 INT
		DECLARE @s2 INT
		
		DECLARE @tmp TABLE
		(
			LotOnSMTId CHAR(12),
			LotId CHAR(12),
			LotSN NVARCHAR(50),
			Qty DECIMAL(18,4),
			_SMTMountLotRowNum INT,
			RowNum INT
		)
		
		DECLARE @tLotOnSMTId CHAR(12)
		DECLARE @tLotId CHAR(12)
		DECLARE @tLotSN NVARCHAR(50)
		DECLARE @tQty DECIMAL(18,4)
		DECLARE @t_SMTMountLotRowNum INT
		DECLARE @IssyQty DECIMAL(18,4)
		
		DECLARE @DataChainAssyIssueId CHAR(12)
		DECLARE @IssueDataChainId CHAR(12)
		
		DECLARE @CheckQty DECIMAL(18,4)
		DECLARE @NONWorkflowStepId CHAR(12)
		DECLARE @UserComment NVARCHAR(50)
		
		SELECT @NONWorkflowStepId = WorkflowStepID 
		FROM workflowstep WITH(NOLOCK) 
		WHERE WorkflowId = @WorkflowID 
		AND Specificationid ='SPE10000008G'
		
		--IF ISNULL(@NONWorkflowStepId,'')=''
		-- BEGIN
		--	DECLARE @wn NVARCHAR(50)
		--	SELECT @wn=ISNULL(dbo.WorkflowRoot.WorkflowName,'N/A') FROM dbo.Workflow WITH(NOLOCK) 
		--	LEFT JOIN dbo.WorkflowRoot WITH(NOLOCK) ON dbo.Workflow.WorkflowRootId = dbo.WorkflowRoot.WorkflowRootId
		--	WHERE WorkflowId=@WorkflowID
			
		--	SET @I_ReturnMessage='ServerMessage:工作流【'+@wn+'】中没有找到二次投板节点!'
		--	RAISERROR(@I_ReturnMessage,16,1)
		-- END
		
		DECLARE @DataChainTable TABLE
		(
			DataChainId CHAR(12),
			LotId CHAR(12),
			MOId CHAR(12),
			ProductId CHAR(12),
			Qty DECIMAL(18,4),
			SpecificationId CHAR(12),
			WorkflowStepId CHAR(12),
			TxnCode VARCHAR(10),
			MOItemId CHAR(12)
		)
		DECLARE @DataChainAssyIssueTable TABLE
		(
			DataChainAssyIssueId CHAR(12),
			AssyDataChainId CHAR(12),
			IssueDataChainId CHAR(12),
			AssyIssueType CHAR(1),
			AssyMOID CHAR(12),
			AssyLotId CHAR(12),
			IssueLotId CHAR(12),
			IssueQty DECIMAL(18,4),
			ResourceId CHAR(12),
			UserId CHAR(12),
			SpecificationId CHAR(12),
			WorkflowStepId CHAR(12),
			IsReplaceProduct BIT
		)
		DECLARE @LotTable TABLE
		(
		    LotOnSMTId CHAR(12),  --add by Jason.Wang 20170311
			LotId CHAR(12),
			Qty DECIMAL(18,4)
		)
		DECLARE @LotOnSMTTable TABLE
		(
			LotOnSMTId CHAR(12)
		)
		
		DECLARE @DataChainMove TABLE 
		(
			DataChainMoveId CHAR(12),
			DataChainId CHAR(12),
			LotId CHAR(12),
			MOId CHAR(12),
			MOItemId CHAR(12),
			Qty CHAR(12),
			NonStdMoveReasonId CHAR(12),
			IsNonStdMove BIT,
			WorkflowStepId CHAR(12),
			ToWorkflowStepId CHAR(12),
			WorkflowId CHAR(12),
			ToWorkflowId CHAR(12),
			LotInDate DATETIME,
			LotOutDate DATETIME,
			CycleTime1 DECIMAL(18,4),
			CycleTime2 DECIMAL(18,4)
		 )
		
		DECLARE 
		@MoveMOId CHAR(12),
		@MoveMOItemId CHAR(12),
		@MoveWorkflowId CHAR(12),
		@MoveLatestMoveDate DATETIME,
		@MoveSpecificationId CHAR(12),
		@MoveWorkflowStepId CHAR(12),
		@LatestMoveDate DATETIME
		


 		SET @i=1
		WHILE @i<=@LotSNCount
		 BEGIN
			SELECT @LotId=LotId,@LotSN=LotSN,@LotProductId=ProductId,@LotQty=Qty,
				   @MoveMOId=MOId,@MoveMOItemId=MOItemId,@MoveWorkflowId=WorkflowId,@MoveLatestMoveDate=LatestMoveDate,
				   @MoveSpecificationId=SpecificationId,@MoveWorkflowStepId=WorkflowStepId,
				   @LatestMoveDate=LatestMoveDate
			 FROM @LinkLotSN WHERE RowNum=@i
			
			EXEC SysGetObjectPKid '','DataChain',@AssyDataChainId OUTPUT
			INSERT INTO @DataChainTable
			        ( DataChainId ,
			          LotId ,
			          MOId ,
			          ProductId ,
			          Qty ,
			          SpecificationId ,
			          WorkflowStepId,
			          TxnCode,MOItemId
			        )
			VALUES  ( @AssyDataChainId , -- DataChainId - char(12)
			          @LotId , -- LotId - char(12)
			          @MOID , -- MOId - char(12)
			          @LotProductId , -- ProductId - char(12)
			          @LotQty , -- Qty - decimal
			          @SpecificationId , -- SpecificationId - char(12)
			          @WorkflowStepId,  -- WorkflowStepId - char(12)
			          'SMTASSY',@MoveMOItemId
			        )
			
			--产生数据链
			--EXEC	[dbo].[TxnBase_DataChainMainLine]
			--		@DataChainId = @AssyDataChainId OUTPUT,
			--		@TxnCode ='SMTASSY',
			--		@I_PlugInCommand = @I_PlugInCommand,
			--		@I_OrBitUserId = @I_OrBitUserId,
			--		@I_ResourceId = @I_ResourceId,
			--		@LotId = @LotId,
			--		@MOID = @MOID,
			--		@ProductId = @LotProductId,
			--		@Qty = @LotQty,
			--		@WorkcenterId = @WorkcenterId,
			--		@SpecificationId = @SpecificationId,
			--		@WorkflowStepId = @WorkflowStepId
					
			IF @IsSMTMountRequired='true' --循环扣料
			 BEGIN
			      
				SELECT @s1=COUNT(1),@i1=1 FROM @_StationNoSlot
				 DECLARE @linkSlotNOROW INT -- linkSLotNO's position 
				 DECLARE @linkSlotNOqty FLOAT -- LinkSLotNO's qty 
				 DECLARE @row_id INT  --- current rowid 
				 DECLARE @linklotid NVARCHAR(50)
				 SET @linkSlotNOrow =0
				 SET @linkSlotNoqty=0
				
				WHILE @i1<=@s1  --循环料站表，找出依次要扣的物料
				 BEGIN
					
					SELECT @StationNo=StationNO,
						   @SLotNO=SLotNO,
						   @BaseQty=BaseQty 
					   FROM @_StationNoSlot 
					   WHERE RowNum=@i1
					
					DELETE @tmp
					
					SET  @temp_issueqty=0
					
					INSERT INTO @tmp --得到要扣料的物料列表
					SELECT LotOnSMTId,LotId,LotSN,CASE WHEN Qty<=0 THEN 0 ELSE Qty END AS Qty,
						   RowNum AS _SMTMountLotRowNum,
						   ROW_NUMBER()OVER(ORDER BY LotOnSMTId ASC) AS RowNum
					   FROM @_SMTMountLot
					   WHERE StationNO=@StationNo
						 AND SLotNO=@SLotNO
						 AND Qty>0
					   ORDER BY CreateDate ASC
	 			     SELECT @LinkSLotNO=linkSlotNO ,@row_id=rownum  from @_SMTMountLot WHERE StationNO=@StationNo AND SLotNO=@SLotNO
					SELECT @s2=COUNT(1),@i2=1 FROM @tmp 
					
					---------------when SlotNo have no qyt then linkSlotNO   ---qinyp20150209------
				     IF @s2=0 AND  @moid IN ('MOD100003HOJ')   AND ISNULL(@LinkSLotNO,'')<>''
				     BEGIN 
				       DELETE  @tmp  
				      INSERT INTO @tmp --得到要扣料的物料列表
					SELECT LotOnSMTId,LotId,LotSN,CASE WHEN Qty<=0 THEN 0 ELSE Qty END AS Qty,
						   RowNum AS _SMTMountLotRowNum,
						   ROW_NUMBER()OVER(ORDER BY LotOnSMTId ASC) AS RowNum
					   FROM @_SMTMountLot
					   WHERE StationNO=@StationNo
						 AND SLotNO=@LinkSLotNO
						 AND Qty>0
				        SELECT @s2=COUNT(1),@i2=1 FROM @tmp 
				     END 
				     --------  end  when SlotNo have no qyt then linkSlotNO -------
					WHILE @i2<=@s2 --循环扣料
					 BEGIN
					 
						SELECT @tLotOnSMTId=LotOnSMTId,
							   @tLotId=LotId,
							   @tLotSN=LotSN,
							   @tQty=Qty,
							   @t_SMTMountLotRowNum=_SMTMountLotRowNum 
						   FROM @tmp WHERE RowNum=@i2
						   
						IF @BaseQty>@tQty
						 BEGIN
						    
							SET @IssyQty=@tQty
						    SET @temp_issueqty=@IssyQty+@temp_issueqty
							 ----************************ add linkSlotNo check  qinyp 20150208 -------
							IF @moid IN ('MOD100003HOJ')AND @i2=@s2-1
							BEGIN 
							    IF ISNULL(@linkSlotNO,'')<>'' AND upper(ISNULL(@LinkSlotNO,''))<>UPPER(@SlotNO)
							    BEGIN 
							          SELECT @linkSlotNOrow=RowNum ,@linkSlotNOqty=qty ,@linkLotid =lotid FROM  @_SMTMountLot WHERE StationNO=@StationNo AND SLotNO=@linkSLotNo
							          IF  (@tqty+ISNULL(@linkSlotNOqty,0))>=@BaseQty
							           BEGIN 
							                SET @linkSlotNOqty=@baseqty-@tqty   --get the required qty  
							                  
							                                                                                    EXEC SysGetObjectPKid '','DataChain',@IssueDataChainId OUTPUT
						         INSERT INTO @DataChainTable
										( DataChainId ,
										  LotId ,
										  MOId ,
										  ProductId ,
										  Qty ,
										  SpecificationId ,
										  WorkflowStepId,
										  TxnCode,MOItemId
										)
								VALUES  ( @IssueDataChainId , -- DataChainId - char(12)
										  @linkLotid , -- LotId - char(12)
										  @MOID , -- MOId - char(12)
										  @SMTProductId , -- ProductId - char(12)
										  @linkSlotNOqty , -- Qty - decimal
										  @SpecificationId , -- SpecificationId - char(12)
										  @WorkflowStepId,  -- WorkflowStepId - char(12)
										  'SMTISSUE',''  )                                        
                       EXEC SysGetObjectPKid '','DataChainAssyIssue',@DataChainAssyIssueId  OUTPUT
						INSERT INTO @DataChainAssyIssueTable  (
												DataChainAssyIssueId,
												AssyDataChainId,
												IssueDataChainId,
												AssyIssueType,
												AssyMOID,
												AssyLotId,
												IssueLotId,
												IssueQty,
												ResourceId,
												UserId,
												SpecificationId,
												WorkflowStepId,
												IsReplaceProduct
											)
										VALUES(
												@DataChainAssyIssueId,
												@AssyDataChainId,
												@IssueDataChainId,
												'',
												@MOID,
												@LotId,
												@tLotId,
												@IssyQty,
												@I_ResourceId,
												@I_OrBitUserId,
												@SpecificationId,
												@WorkflowStepId,
												'false'
											) 
							                
							                  IF NOT EXISTS (SELECT 1 FROM @linkLOtNO_table WHERE row=@linkSlotNOrow)
							                  BEGIN 
							                  INSERT @LinkLotNO_table 
							                  (row ,qty,lotid )
							                  VALUES (@linkSlotNORow,@LinkSlotNOqty,@linkLotid )
							                 END  
							                 ELSE 
							                 BEGIN 
							                 
							                    UPDATE @linkLotNO_table SET qty=@linkSLotNoqty+qty 
							                    WHERE row=@linkSlotNOROW
							                 END 
							           
							           END 
							        
							    
							    END 
							    ELSE BEGIN 
							    
							    
							       	SET @IssyQty=@tQty
							       	
							    
							   END 
							    
							
							END
							  
							  ------- end link check ************************************ ------------------------------ 
						 END
						  
						 ELSE
						 BEGIN
							SET @IssyQty=@BaseQty-@temp_issueqty
							SET @temp_issueqty=@IssyQty+@temp_issueqty
						 END
						 
						
						INSERT INTO @bindLotSN
						SELECT @LotSN AS LotSN,
						       @tLotSN AS ProductLotSN,
						       @IssyQty AS Qty,
						       @bindLotSNRowNum AS rowNum
						       
						SET @bindLotSNRowNum=@bindLotSNRowNum+1
						 

						 --不取issueid
						--EXEC SysGetObjectPKid '','DataChain',@IssueDataChainId OUTPUT
						--INSERT INTO @DataChainTable
						--				( DataChainId ,
						--				  LotId ,
						--				  MOId ,
						--				  ProductId ,
						--				  Qty ,
						--				  SpecificationId ,
						--				  WorkflowStepId,
						--				  TxnCode,MOItemId
						--				)
						--		VALUES  ( @IssueDataChainId , -- DataChainId - char(12)
						--				  @tLotId , -- LotId - char(12)
						--				  @MOID , -- MOId - char(12)
						--				  @SMTProductId , -- ProductId - char(12)
						--				  @IssyQty , -- Qty - decimal
						--				  @SpecificationId , -- SpecificationId - char(12)
						--				  @WorkflowStepId,  -- WorkflowStepId - char(12)
						--				  'SMTISSUE',''
						--				)
						 --不取issueid

						--产生数据链
						--EXEC	[dbo].[TxnBase_DataChainMainLine]
						--		@DataChainId = @IssueDataChainId OUTPUT,
						--		@TxnCode ='SMTISSUE',
						--		@I_PlugInCommand = @I_PlugInCommand,
						--		@I_OrBitUserId = @I_OrBitUserId,
						--		@I_ResourceId = @I_ResourceId,
						--		@LotId = @tLotId,
						--		@MOID = @MOID,
						--		@ProductId = @SMTProductId,
						--		@Qty = @IssyQty,
						--		@WorkcenterId = @WorkcenterId,
						--		@SpecificationId = @SpecificationId,
						--		@WorkflowStepId = @WorkflowStepId
								
						--装配明细
						EXEC SysGetObjectPKid '','DataChainAssyIssue',@DataChainAssyIssueId  OUTPUT
						INSERT INTO @DataChainAssyIssueTable  (
												DataChainAssyIssueId,
												AssyDataChainId,
												IssueDataChainId,
												AssyIssueType,
												AssyMOID,
												AssyLotId,
												IssueLotId,
												IssueQty,
												ResourceId,
												UserId,
												SpecificationId,
												WorkflowStepId,
												IsReplaceProduct
											)
										VALUES(
												@DataChainAssyIssueId,
												@AssyDataChainId,
												null,--z置空
												'',
												@MOID,
												@LotId,
												@tLotId,
												@IssyQty,
												@I_ResourceId,
												@I_OrBitUserId,
												@SpecificationId,
												@WorkflowStepId,
												'false'
											) 
					    --INSERT INTO DataChainAssyIssue  (
									--			DataChainAssyIssueId,
									--			AssyDataChainId,
									--			IssueDataChainId,
									--			AssyIssueType,
									--			AssyMOID,
									--			AssyLotId,
									--			IssueLotId,
									--			IssueQty,
									--			ResourceId,
									--			UserId,
									--			SpecificationId,
									--			WorkflowStepId,
									--			IsReplaceProduct
									--		)
									--	VALUES(
									--			@DataChainAssyIssueId,
									--			@AssyDataChainId,
									--			@IssueDataChainId,
									--			'',
									--			@MOID,
									--			@LotId,
									--			@tLotId,
									--			@IssyQty,
									--			@I_ResourceId,
									--			@I_OrBitUserId,
									--			@SpecificationId,
									--			@WorkflowStepId,
									--			'false'
									--		) 
											
						--UPDATE Lot SET @CheckQty=Qty,
						--			   Qty=Qty-@IssyQty,
						--			   LatestActivityDate=GETDATE()
						--		 WHERE LotId=@tLotId
						
				 
						IF EXISTS(SELECT 1 FROM @LotTable WHERE LotId=@tLotId)
						 BEGIN
							UPDATE @LotTable SET Qty=ISNULL(Qty,0)+@IssyQty WHERE LotId=@tLotId
						 END
						ELSE
						 BEGIN
							INSERT INTO @LotTable(LotOnSMTId,LotId,Qty)VALUES(@tLotOnSMTId,@tLotId,@IssyQty)  --add @tLotOnSMTId by Jason.Wang 20170311
						 END
						--IF @CheckQty>=0 AND @CheckQty!=@tQty
						-- BEGIN
						--	SET @I_ReturnMessage='ServerMessage:物料批号【'+ISNULL(@tLotSN,'N/A')+'】数量发生了改变(原始数量为：'+CONVERT(NVARCHAR(50),@tQty)+'	现在数量为：'+CONVERT(NVARCHAR(50),@CheckQty)+'),导致扣料失败!'
						--	RAISERROR(@I_ReturnMessage,16,1)
						-- END
						UPDATE @_SMTMountLot SET Qty=Qty-@IssyQty WHERE LotId=@tLotId
						
					    UPDATE @tmp SET Qty=Qty-@IssyQty WHERE LotId=@tLotId
					    
						IF @IssyQty>=@tQty
						 BEGIN
							--DELETE dbo.LotOnSMT WHERE LotOnSMTId=@tLotOnSMTId
							INSERT INTO @LotOnSMTTable(LotOnSMTId)VALUES(@tLotOnSMTId)
						 END
					    
						IF @BaseQty-@temp_issueqty=0
						 BEGIN
							BREAK
						 END
						--ELSE
						-- BEGIN
						--	SET @IssyQty=@BaseQty-@IssyQty
						-- END
						SET @i2=@i2+1
					 END
					 
					SET @i1=@i1+1
				 END
		     END
		     
			--IF @MOSMTPath = '0' OR EXISTS (
			--								SELECT 1 FROM  DataChainPCBStart WITH(NOLOCK) 
			--								WHERE LotID = @LotID 
			--								AND StartCount >= 2
			--							 )
			-- BEGIN 
				--PRINT '1'
				
		
				
				
				--EXEC [dbo].[TxnBase_LotMove]
				--		@I_ReturnMessage = @I_ReturnMessage OUTPUT,
				--		@I_PlugInCommand = @I_PlugInCommand,
				--		@I_OrBitUserId = @I_OrBitUserId,
				--		@I_ResourceId = @I_ResourceId ,
				--		@LotSN = @LotSN
						
				--move
				
				DECLARE @MoveDataChainId CHAR(12)
				EXEC SysGetObjectPKid '','DataChain',@MoveDataChainId OUTPUT
				INSERT INTO @DataChainTable
				        ( DataChainId ,
				          LotId ,
				          MOId ,
				          MOItemId ,
				          Qty ,
				          TxnCode ,
				          ProductId ,
				          SpecificationId ,
				          WorkflowStepId 
				        )
				VALUES(
						  @MoveDataChainId,
						  @LotId,
						  @MoveMOId,
						  @MoveMOItemId,
						  @LotQty,
						  'MOVE',
						  @LotProductId,
						  @ToSpeicifcationId,
						  @ToWorkflowStepId
						  
				)
			
				DECLARE @MoveDataChainMoveId CHAR(12)
				EXEC SysGetObjectPKid '','DataChainMove',@MoveDataChainMoveId OUTPUT
				INSERT INTO @DataChainMove  (
								DataChainMoveId ,
								DataChainId ,
								LotId ,
								MOId ,
								MOItemId ,
								Qty ,
								NonStdMoveReasonId ,
								IsNonStdMove ,
								WorkflowStepId ,
								ToWorkflowStepId ,
								WorkflowId ,
								ToWorkflowId ,
								LotInDate ,
								LotOutDate ,
								CycleTime1,
								CycleTime2 
								)
							VALUES
							(
								@MoveDataChainMoveId,
								@MoveDataChainId,
								@LotId,
								@MoveMOId,
								@MoveMOItemId,
								@LotQty,
								'',
								0,
								@MoveWorkflowStepId,
								@ToWorkflowStepId,
								@MoveWorkflowId,
								@MoveWorkflowId,
								GETDATE(),
								GETDATE(),
								CAST(GETDATE()-@LatestMoveDate AS DECIMAL(18,3)) ,
								0
							)
				
				
			 --END 
		     --ELSE 
			 --BEGIN 
			 
			 -- IF ISNULL(@NONWorkflowStepId,'')=''
				--BEGIN
				--	DECLARE @wn NVARCHAR(50)
				--	SELECT @wn=ISNULL(dbo.WorkflowRoot.WorkflowName,'N/A') FROM dbo.Workflow WITH(NOLOCK) 
				--	LEFT JOIN dbo.WorkflowRoot WITH(NOLOCK) ON dbo.Workflow.WorkflowRootId = dbo.WorkflowRoot.WorkflowRootId
				--	WHERE WorkflowId=@WorkflowID
					
				--	SET @I_ReturnMessage='ServerMessage:工作流【'+@wn+'】中没有找到二次投板节点!'
				--	RAISERROR(@I_ReturnMessage,16,1)
				--END
			 
				----PRINT '2'
			 --   IF @PCBType = 'AB面板'
			 --    BEGIN
				--	SET @UserComment='AB面板二次投板'
			 --    END
			 --   ELSE IF @PCBType = '阴阳板'
			 --    BEGIN
				--	SET @UserComment='阴阳面板二次投板'
			 --    END
			    
				--EXEC [dbo].[TxnBase_LotNonStdMove]
				--@I_ReturnMessage = @I_ReturnMessage OUTPUT,
				--@I_PlugInCommand = @I_PlugInCommand,
				--@I_OrBitUserId = @I_OrBitUserId,
				--@I_ResourceId =  @I_ResourceId,
				--@LotSN =@LotSN,
				--@NonStdMoveReasonId = '',
				--@TargetWorkflowId = @WorkflowID,				--流程名称
				--@TargetWorkflowStepId = @NONWorkflowStepId,				--规程节点名称
				--@TargetStack = '',
				----@UserComment = ''
				--@UserComment = @UserComment
				--PRINT @WorkflowID
				--PRINT @NONWorkflowStepId
			 --END 	
			SET @i=@i+1
		 END
        --IF @moid  IN ('MOD100003HOG','MOD100003HOJ','MOD100003MI6')
        IF ISNULL(@IsJITMode,0)=1
         BEGIN 
              IF EXISTS (SELECT 1 FROM @linklotNO_table )
              BEGIN 

			     DECLARE @TestTime DATETIME
                 SET @TestTime=GETDATE()
		------------------------------------Jason.Wang 2015.06.26-----------------------------------------------------------------
                 --DECLARE @cursor_lotid NVARCHAR(50)=''
                
                 --DECLARE curlotid CURSOR FOR SELECT lotid FROM @linklotNO_table 
                 --OPEN curlotid 
                 --FETCH NEXT FROM curlotid INTO @cursor_lotid 
                 --  WHILE @@fetch_status =0 
                 --  BEGIN 
                 --      SELECT @linkSlotNOqty =qty FROM @linkLOtNO_table WHERE lotid=@cursor_lotid  
                 --      UPDATE @lotTable SET qty=@linkSLotNOqty+qty WHERE lotid=@cursor_lotid  
                 --    FETCH NEXT FROM curlotid INTO @cursor_lotid 
                 --  END 
                 
				 UPDATE lotTable SET  lotTable.qty+=linkLOtNO_table.qty from  @lotTable AS lotTable 
				 INNER JOIN @linkLOtNO_table AS linkLOtNO_table ON lotTable.lotid=linkLOtNO_table.lotid

				  
        -----------------------------------end Jason.Wang 2015.06.26-----------------------------------------------------------------          
                 INSERT INTO dbo.CatchErooeLog( ProcName , ErooeCommad , CreateDate ,ResultTime )VALUES  ( N'Txn_SMTIssueExeNew' , N'IsJITMode1' , GETDATE() ,DATEDIFF(SECOND,@TestTime,GETDATE()) )
				 --INSERT INTO dbo.CatchErooeLog( ProcName , ErooeCommad , CreateDate  )VALUES  ( N'Txn_SMTIssueExeNew' , N'IsJITMode' , GETDATE() )
              
              END 
            
         
        END 


		--------------------------简单健壮性判断 因为存在网络卡顿或者服务器异常情况-----------------
		DECLARE @current_specid CHAR(12)
		sELECT @current_specid= SpecificationId FROM  lot WITH(NOLOCK) WHERE lotsn=@LotSN
		IF  ISNULL(@current_specid,'')NOT IN  ('SPE10000004N','SPE1000000DN')
		BEGIN
		INSERT INTO  dbo.CatchErooeLog
		( ProcName ,
		ErooeCommad ,
		CreateDate ,
		Duration ,
		ResultTime
		)
		VALUES  ( N'Txn_SMTIssueExeNew' , -- ProcName - nvarchar(50)
		@lotsn+',已不在当前站点' , -- ErooeCommad - nvarchar(500)
		GETDATE() , -- CreateDate - datetime
		0 , -- Duration - int
		0  -- ResultTime - int
		)
		SET @I_ReturnMessage='服务器贴片中发生致命性错误,请重试！！'
			SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
			return -1

		END
		--------------------------简单健壮性判断 因为存在网络卡顿或者服务器异常情况-----------------


         BEGIN 
		UPDATE dbo.Lot SET Qty=CASE WHEN Lot.Qty>A.Qty THEN Lot.Qty-A.Qty ELSE 0 END
		FROM dbo.Lot INNER JOIN @LotTable A ON Lot.LotId=A.LotId
		END 

		------飞达扣数插入数据表，代理扣数20170531 xiezq 
		IF  @WorkcenterName  IN ('S01','S02','S03','S04','S05','S06','S14','S15','S16','S18','S19','S20','S26','S27','S28','S34','S35')
		BEGIN
			INSERT INTO dbo.LotOnSMTDeviceParts
					( LotOnSMTId, LotId, Qty,FeederId,Station,WorkcenterName, Status )
			SELECT LotOnSMT.LotOnSMTId,b.LotId,b.Qty,FeederId,StationNO+SLotNO AS Station,WorkcenterName,'0' AS Station  FROM dbo.LotOnSMT WITH(NOLOCK) INNER JOIN @lottable b ON dbo.LotOnSMT.LotId=b.lotid
			INNER JOIN dbo.WorkCenter WITH(NOLOCK) ON ShortName=SMTLineNO  
			WHERE MOId=@moid AND SMTLineNO=@WorkcenterName  AND  ISNULL(FeederId,'')<>'' 			
		END	


		-------------------------25 fd------------
		--SELECT FeederId,b.qty,WorkcenterName,StationNO+SLotNO AS Station INTO #t_4d FROM dbo.LotOnSMT WITH(NOLOCK) INNER JOIN @lottable b ON dbo.LotOnSMT.LotId=b.lotid
		--INNER JOIN dbo.WorkCenter WITH(NOLOCK) ON ShortName=SMTLineNO  --add WorkcenterName、Station by Jason.Wang 2017-03-25
  --      WHERE MOId=@moid AND SMTLineNO=@WorkcenterName  AND  ISNULL(FeederId,'')<>'' 

  --      UPDATE a SET   UsedNum=ISNULL(UsedNum,0)+qty,UpdateTime=GETDATE(),RemainUseNum=CASE 
		--WHEN ISNULL(RemainUseNum,0)>qty THEN ISNULL(RemainUseNum,0)-qty ELSE 0 END , WorkcenterName=b.WorkcenterName,Remarks=b.Station  --add WorkcenterName by Jason.Wang 2017-03-25  --add Remarks 槽位 by chenlu 20170509
  --      FROM  [10.2.0.25].OrBitXE.dbo.[DevicePartsFD]   a 
  --      INNER JOIN #t_4d b  ON a.DevicePartsFDId=b.FeederId

		--IF OBJECT_ID('tempdb..#t_4d') IS NOT NULL	DROP  TABLE  #t_4d
		
		---------------------25 fd------------ 


-- add by ybj 20150713
 IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName, ErooeCommad, Duration) values('Txn_SMTIssueExeNew_debug_9', @debug  , DATEDIFF( SECOND, @time, GETDATE() ) )
			
		DELETE LotOnSMT WHERE EXISTS(SELECT 1 FROM @LotOnSMTTable WHERE LotOnSMTId=LotOnSMT.LotOnSMTId)
		
		INSERT INTO dbo.DataChain
				        ( DataChainId ,
				          LotId ,
				          MOId ,
				          MOItemId ,
				          Qty ,
				          TxnCode ,
				          ProductId ,
				          UserId ,
				          WorkcenterId ,
				          ResourceId ,
				          ShiftId ,
				          SpecificationId ,
				          WorkflowStepId ,
				          PluginId ,
				          CreateDate
				        )
				SELECT DataChainId,
					   LotId,
					   MOId,
					   MOItemId,
					   Qty,
					   TxnCode,
					   ProductId,
					   @I_OrBitUserId,
					   @WorkcenterId,
					   @I_ResourceId,
					   '',
					   SpecificationId,
					   WorkflowStepId,
					   @I_PlugInCommand,
					   GETDATE()
				FROM @DataChainTable
		
		INSERT INTO dbo.DataChainAssyIssue
				        (   DataChainAssyIssueId,
							AssyDataChainId,
							IssueDataChainId,
							AssyIssueType,
							AssyMOID,
							AssyLotId,
							IssueLotId,
							IssueQty,
							ResourceId,
							UserId,
							SpecificationId,
							WorkflowStepId,
							IsReplaceProduct
				        )
				SELECT  DataChainAssyIssueId,
						AssyDataChainId,
						IssueDataChainId,
						AssyIssueType,
						AssyMOID,
						AssyLotId,
						IssueLotId,
						IssueQty,
						ResourceId,
						UserId,
						SpecificationId,
						WorkflowStepId,
						IsReplaceProduct
				FROM @DataChainAssyIssueTable
			
		INSERT INTO DataChainMove  (
				DataChainMoveId,
				DataChainId,
				LotId,
				MOId,
				MOItemId,
				Qty,
				NonStdMoveReasonId,
				IsNonStdMove,
				WorkflowStepId,
				ToWorkflowStepId,
				ResourceId,
				ToResourceId,
				WorkflowId,
				ToWorkflowId,
				ShiftId,
				ToShiftId,
				LotInDate,
				LotOutDate,
				CycleTime1,
				CycleTime2,
				UserId
				)
			SELECT DataChainMoveId,
				   DataChainId,
				   LotId,
				   MOId,
				   MOItemId,
				   Qty,
				   '' AS NonStdMoveReasonId,
				   0 AS IsNonStdMove,
				   WorkflowStepId,
				   ToWorkflowStepId,
				   @I_ResourceId AS ResourceId,
				   @I_ResourceId AS ToResourceId,
				   WorkflowId,
				   ToWorkflowId,
				   '',
				   '',
				   LotInDate,
				   LotOutDate,
				   CycleTime1,
				   CycleTime2,
				   @I_OrBitUserId AS UserId
			FROM @DataChainMove 
				
-- add by ybj 20150713
 IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName, ErooeCommad, Duration) values('Txn_SMTIssueExeNew_debug_9_1', @debug  , DATEDIFF( SECOND, @time, GETDATE() ) )
			
		UPDATE dbo.Lot
		SET WorkFlowStepID=@ToWorkflowStepId,
			SpecificationId=@ToSpeicifcationId,
			WorkCenterId=@WorkCenterId,
			NextWorkFlowStepID=@ToNextWorkflowStepId,
			PreviousWorkflowStepId=WorkflowStepId,
			LatestTxnCode='DC',						
			ResourceID=@I_ResourceId,
			LatestUserId=@I_OrBitUserId,
			ShiftID='',
			LatestMoveDate=GETDATE(),
			LatestActivityDate=GETDATE()
		WHERE EXISTS
		(
			SELECT 1 FROM @LinkLotSN WHERE LotId=Lot.LotId
		)
		
-- add by ybj 20150713
IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName, ErooeCommad, Duration) values('Txn_SMTIssueExeNew_debug_9_2', @debug  , DATEDIFF( SECOND, @time, GETDATE() ) )
			
	--======================================================================================
		IF @IsHuaWeiCustomer ='true'  --如果是华为客户,上传记录到华为表
		BEGIN
			BEGIN TRY
		
				DECLARE @ih INT=1
				DECLARE @sh INT
			
				DECLARE
				@hLotSN NVARCHAR(50),
				@hProductLotSN NVARCHAR(50),
				@hQty DECIMAL(18,4)
				
				SELECT @sh=COUNT(1) FROM @bindLotSN
				
				-----------------------------------------------===========================================================
				DECLARE  @LINE  NVARCHAR(max)
				DECLARE  @DateTime  NVARCHAR(100)
				DECLARE  @wosn_4d  NVARCHAR(100)
				DECLARE  @custmodel  NVARCHAR(100)
				DECLARE  @lotonsmttime DATETIME
				DECLARE  @abside_4d  NVARCHAR(5)
				DECLARE  @lotonsmt_userid NVARCHAR(50)
				SELECT  @LINE=WorkcenterName,@wosn_4d=WOSN, @custmodel= CASE  WHEN ONTProductName IS NULL THEN ' ' WHEN ONTProductName='' THEN ' ' ELSE ONTProductName end  FROM  MO WITH(NOLOCK)
				INNER JOIN  dbo.Product  WITH(NOLOCK)  ON  mo.ProductId=dbo.Product.ProductId
				INNER JOIN  dbo.ProductRoot  WITH(NOLOCK)  ON ProductRoot.ProductRootId = Product.ProductRootId
				INNER  JOIN  dbo.Workcenter WITH(NOLOCK) ON  dbo.MO.WorkCenterID = dbo.Workcenter.WorkcenterId
				WHERE  MOName=@MOName
				SET @DateTime = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),GETDATE(),120),'-',''),':',''),' ','')
	
				DECLARE  @Detail  TABLE(
						num  INT  IDENTITY(1,1),
						RAW_LOT_ID  NVARCHAR(50),
						USE_QTY  NUMERIC(10,3),
						RAW_MAT_ID  nvarchar(100),
						LINE  NVARCHAR(100),
						QTY  DECIMAL(10,3),  --MZ条码原始数量
						SUPPLIER_CODE  NVARCHAR(100),
						SUPPLIER_NAME  NVARCHAR(100),
						STOCK_IN_TIME  NVARCHAR(100), --非时间格式
						LOTE_CODE   NVARCHAR(100),
						RAW_MAT_CREATE_TIME  NVARCHAR(100),  --非时间格式
						HW_RAW_MAT_ID     NVARCHAR(100),
						--MAT_DATE  DATETIME,
						SN09_CODE NVARCHAR(100),
						processid  INT ,
						LOT_ID  NVARCHAR(100),
						lotonsmttime  NVARCHAR(100),
						abside  NVARCHAR(5),
						lotonsmt_userid NVARCHAR(100)
)
				-------------------------------------------------=========================================
		
				WHILE @ih<=@sh
				BEGIN
					SELECT @hLotSN=LotSN,
						@hProductLotSN=ProductLotSN,
						@hQty=Qty
						FROM @bindLotSN WHERE rowNum=@ih
					
				------------------------------------------------------------------------------------------------
					--EXEC dbo.Interface_HuaWei_IINVSUMTMP4D @I_ReturnMessage = @I_ReturnMessage OUTPUT, -- nvarchar(max)
					--	@RAW_LOT_ID = @hProductLotSN, -- nvarchar(128)
					--	@EMS_ORDER_ID = @MOName, -- nvarchar(25)
					--	@LOT_ID = @hLotSN, -- nvarchar(30)
					--	@USE_QTY = @hQty -- decimal	
					
					
					SELECT  TOP 1 @lotonsmttime=CreateDate, @abside_4d= CASE  WHEN ABSide  IS NULL THEN ' ' WHEN ABSide='' THEN ' ' ELSE ABSide END  ,
					@lotonsmt_userid=PDAUserId
					FROM  dbo.LotOnSMTHistory  WITH(NOLOCK) WHERE  LotId=(SELECT LotId FROM lot WITH(NOLOCK) WHERE lotsn=@hProductLotSN) ORDER BY  LotOnSMTHistory.CreateDate DESC


					IF  @lotonsmttime IS  NULL  OR @lotonsmttime=''
					SET @lotonsmttime=GETDATE()
					IF  @abside_4d IS  NULL  OR @abside_4d=''
					SET @abside_4d='  '
					IF  @lotonsmt_userid IS  NULL  OR @lotonsmt_userid=''
					SET @lotonsmt_userid='  '

					
					INSERT INTO  @Detail
		( --num ,
		RAW_LOT_ID ,
		USE_QTY ,
		RAW_MAT_ID ,
		LINE ,
		QTY ,
		SUPPLIER_CODE ,
		SUPPLIER_NAME ,
		STOCK_IN_TIME ,
		LOTE_CODE ,
		RAW_MAT_CREATE_TIME ,
		HW_RAW_MAT_ID ,
		--MAT_DATE ,
		SN09_CODE ,
		processid,
		LOT_ID,
				lotonsmttime ,
						abside ,
						lotonsmt_userid
		)
		SELECT @hProductLotSN AS RAW_LOT_ID, @hQty AS USE_QTY, ProductName AS RAW_MAT_ID, @LINE AS LINE, dbo.POItemLot.LotQty AS QTY,
		Client.Code1 AS SUPPLIER_CODE, VendorDescription AS SUPPLIER_NAME, REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),dbo.POItemLot.CreateDate,120),'-',''),':',''),' ','') AS STOCK_IN_TIME,
			ProductionLot AS LOTE_CODE, GRNLot AS RAW_MAT_CREATE_TIME,  REPLACE(REPLACE(ProductName,'M004-',''),'K004-','') AS HW_RAW_MAT_ID,
			POItemLot.PSN AS SN09_CODE,  (CAST(ceiling(rand() * 19) as int)+1) AS processid,@hLotSN AS LOT_ID,
			REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),@lotonsmttime,120),'-',''),':',''),' ','') AS lotonsmttime,
			@abside_4d,@lotonsmt_userid
			FROM dbo.POItemLot WITH (NOLOCK)
			INNER JOIN dbo.POItem WITH (NOLOCK) ON POItem.POItemId = POItemLot.POItemId
			INNER JOIN dbo.PO WITH (NOLOCK) ON PO.POId = POItem.POId
			INNER JOIN dbo.Vendor WITH (NOLOCK) ON Vendor.VendorId = PO.VendorId
			INNER JOIN dbo.ProductRoot WITH (NOLOCK) ON DefaultProductId = POItem.ProductID
			inner JOIN   dbo.Client  WITH  (NOLOCK) ON  client.ClientSN=POItemLot.ClientSN
			WHERE LotSN = @hProductLotSN

					
				
					
	

				------------------------------------------------------------------------------------------------
					SET @ih=@ih+1
				END
				UPDATE  @Detail   SET  SN09_CODE='N/A'  WHERE SN09_CODE='' OR  SN09_CODE IS  NULL	
				UPDATE  @Detail   SET  SUPPLIER_CODE='ZOWEE'  WHERE SUPPLIER_CODE='' OR  SUPPLIER_CODE IS  NULL
				UPDATE  @Detail   SET  LOTE_CODE='N/A'  WHERE LOTE_CODE='' OR  LOTE_CODE IS  NULL	
			
				INSERT INTO [OEM_HUAWEI].[HUAWEI].dbo.TRIINVLOTSTS
	( MOVE_FLAG ,
	MOVE_TIME ,
	FACTORY ,
	RETURN_FLAG ,
	EMS_ORDER_ID ,
	RAW_MAT_ID ,
	OLD_RAW_LOT_ID ,
	RAW_LOT_ID ,
	LINE ,
	UNIT ,
	QTY ,
	SUPPLIER_RAW_MAT_CODE ,
	SUPPLIER_CODE ,
	SUPPLIER_NAME ,
	STOCK_IN_TIME ,
	LOTE_CODE ,
	RAW_MAT_CREATE_TIME ,
	GETFLAG ,
	GETTIME ,
	ACTIONFLAG ,
	HW_RAW_MAT_ID ,
	LOT_ID ,
	USE_QTY ,
	SMT_FLAG ,
	SN09_CODE ,
	PSN_CODE ,
	process_id,
			tran_time,	cmf_1,	cmf_2,	cmf_3,	cmf_4,	cmf_5
	)
	SELECT
	'I' , -- MOVE_FLAG - char(1)
	@DateTime  , -- MOVE_TIME - nvarchar(14)
	N'ZHUOYI' , -- FACTORY - nvarchar(10)
	'N' , -- RETURN_FLAG - char(1)
	@moname , -- EMS_ORDER_ID - nvarchar(25)
	RAW_MAT_ID , -- RAW_MAT_ID - nvarchar(30)
	N'NA' , -- OLD_RAW_LOT_ID - nvarchar(128)
	RAW_LOT_ID, -- RAW_LOT_ID - nvarchar(128)
	LINE , -- LINE - nvarchar(20)
	N'PCS' , -- UNIT - nvarchar(16)
	QTY , -- QTY - decimal
	N'NA' , -- SUPPLIER_RAW_MAT_CODE - nvarchar(128)
	SUPPLIER_CODE , -- SUPPLIER_CODE - nvarchar(64)
	SUPPLIER_NAME , -- SUPPLIER_NAME - nvarchar(64)
	STOCK_IN_TIME , -- STOCK_IN_TIME - nvarchar(14)
	LOTE_CODE , -- LOTE_CODE - nvarchar(64)
	RAW_MAT_CREATE_TIME , -- RAW_MAT_CREATE_TIME - nvarchar(64)
	0 , -- GETFLAG - numeric
	@DateTime , -- GETTIME - nvarchar(14)
	N'I' , -- ACTIONFLAG - nvarchar(2)
	HW_RAW_MAT_ID , -- HW_RAW_MAT_ID - nvarchar(30)
	LOT_ID , -- LOT_ID - nvarchar(64)
	USE_QTY , -- USE_QTY - nvarchar(64)
	'Y' , -- SMT_FLAG - char(1)
	ISNULL(SN09_CODE, 'N/A' ) , -- SN09_CODE - nvarchar(64)
	ISNULL(SN09_CODE, 'N/A' ) , -- PSN_CODE - nvarchar(64)
	processid , -- process_id - int
			lotonsmttime,
			abside,
			lotonsmt_userid,
			@wosn_4d,
			@custmodel,
			' '
FROM @detail
				
	
			END TRY
			BEGIN CATCH
				SET @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】贴片成功,但上传到华为记录表中失败1!  '
				insert into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SMTIssueExeNew_Huawei',ISNULL(ERROR_MESSAGE(),'上传到华为记录表中失败1') + ISNULL(@I_ReturnMessage, '') )-- add by ybj 20141016				
				SELECT  0 AS I_ReturnValue,@I_ReturnMessage as I_ReturnMessage
				RETURN 0
			END CATCH
		END
		--==================================================================================================================
		
		END TRY	
		BEGIN CATCH

				SET @I_ReturnMessage='ServerMessage:'+ISNULL(ERROR_MESSAGE(),'扣料出错异常,请重试!')
				SELECT  -1 AS I_ReturnValue,@I_ReturnMessage AS I_ReturnMessage
				RETURN -1
		END CATCH

	   
	   --=====================mes+部分=====================================================2017.06.23
	    DECLARE  @ismesaddcustomer bit
		EXEC dbo.txn_IsMesAddCustomer
		@MOID = @moid, -- char(12)
		@IsMesAdd = @ismesaddcustomer out -- bit
        DECLARE  @nowtime4d NVARCHAR(50)= REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),GETDATE(),120),'-',''),':',''),' ','')
		IF  @ismesaddcustomer='true'
		BEGIN
		
	
				DECLARE @ih_add INT=1
				DECLARE @sh_add INT
			
				DECLARE
				@hLotSN_add NVARCHAR(50),
				@hProductLotSN_add NVARCHAR(50),
				@hQty_add DECIMAL(18,4)
				
				SELECT @sh_add=COUNT(1) FROM @bindLotSN
				
				-----------------------------------------------===========================================================
				DECLARE  @LINE_add  NVARCHAR(max)
				DECLARE  @DateTime_add  NVARCHAR(100)
				DECLARE  @wosn_4d_add  NVARCHAR(100)
				DECLARE  @custmodel_add  NVARCHAR(100)
				DECLARE  @lotonsmttime_add DATETIME
				DECLARE  @abside_4d_add  NVARCHAR(5)
				DECLARE  @lotonsmt_userid_add NVARCHAR(50)
				SELECT  @LINE_add=WorkcenterName,@wosn_4d_add=WOSN, @custmodel_add= CASE  WHEN ONTProductName IS NULL THEN ' ' WHEN ONTProductName='' THEN ' ' ELSE ONTProductName end  FROM  MO WITH(NOLOCK)
				INNER JOIN  dbo.Product  WITH(NOLOCK)  ON  mo.ProductId=dbo.Product.ProductId
				INNER JOIN  dbo.ProductRoot  WITH(NOLOCK)  ON ProductRoot.ProductRootId = Product.ProductRootId
				INNER  JOIN  dbo.Workcenter WITH(NOLOCK) ON  dbo.MO.WorkCenterID = dbo.Workcenter.WorkcenterId
				WHERE  MOName=@MOName
				SET @DateTime_add = REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),GETDATE(),120),'-',''),':',''),' ','')
	
				DECLARE  @Detail_add  TABLE(
						num  INT  IDENTITY(1,1),
						RAW_LOT_ID  NVARCHAR(50),
						USE_QTY  NUMERIC(10,3),
						RAW_MAT_ID  nvarchar(100),
						LINE  NVARCHAR(100),
						QTY  DECIMAL(10,3),  --MZ条码原始数量
						SUPPLIER_CODE  NVARCHAR(100),
						SUPPLIER_NAME  NVARCHAR(100),
						STOCK_IN_TIME  NVARCHAR(100), --非时间格式
						LOTE_CODE   NVARCHAR(100),
						RAW_MAT_CREATE_TIME  NVARCHAR(100),  --非时间格式
						HW_RAW_MAT_ID     NVARCHAR(100),
						--MAT_DATE  DATETIME,
						SN09_CODE NVARCHAR(100),
						processid  INT ,
						LOT_ID  NVARCHAR(100),
						lotonsmttime  NVARCHAR(100),
						abside  NVARCHAR(5),
						lotonsmt_userid NVARCHAR(100)
)
				-------------------------------------------------=========================================
		
				WHILE @ih_add<=@sh_add
				BEGIN
					SELECT @hLotSN_add=LotSN,
						@hProductLotSN_add=ProductLotSN,
						@hQty_add=Qty
						FROM @bindLotSN WHERE rowNum=@ih_add
					
				
					
					SELECT  TOP 1 @lotonsmttime_add=CreateDate,
					@abside_4d_add= CASE  WHEN ABSide  IS NULL THEN ' ' WHEN ABSide='' THEN ' ' ELSE ABSide END  ,
					@lotonsmt_userid_add=PDAUserId
					FROM  dbo.LotOnSMTHistory  WITH(NOLOCK) WHERE  LotId=(SELECT LotId FROM lot WITH(NOLOCK) WHERE lotsn=@hProductLotSN_add) ORDER BY  LotOnSMTHistory.CreateDate DESC


					IF  @lotonsmttime_add IS  NULL  OR @lotonsmttime_add=''
					SET @lotonsmttime_add=GETDATE()
					IF  @abside_4d_add IS  NULL  OR @abside_4d_add=''
					SET @abside_4d_add='  '
					IF  @lotonsmt_userid_add IS  NULL  OR @lotonsmt_userid_add=''
					SET @lotonsmt_userid_add='  '

					
					INSERT INTO  @Detail_add
					(
							--num ,
					RAW_LOT_ID ,
					USE_QTY ,
					RAW_MAT_ID ,
					LINE ,
					QTY ,
					SUPPLIER_CODE ,
					SUPPLIER_NAME ,
					STOCK_IN_TIME ,
					LOTE_CODE ,
					RAW_MAT_CREATE_TIME ,
					HW_RAW_MAT_ID ,
					SN09_CODE ,
					--processid ,
					LOT_ID ,
					lotonsmttime ,
					abside ,
					lotonsmt_userid
					)
					
				SELECT @hProductLotSN_add AS RAW_LOT_ID, @hQty_add AS USE_QTY, ProductName AS RAW_MAT_ID, @LINE_add AS LINE, dbo.POItemLot.LotQty AS QTY,
				Client.Code1 AS SUPPLIER_CODE, VendorDescription AS SUPPLIER_NAME, REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),dbo.POItemLot.CreateDate,120),'-',''),':',''),' ','') AS STOCK_IN_TIME,
					ProductionLot AS LOTE_CODE, GRNLot AS RAW_MAT_CREATE_TIME,   REPLACE(REPLACE(REPLACE(ProductName,'M004-',''),'K004-',''),'K290-','') AS HW_RAW_MAT_ID,
					POItemLot.PSN AS SN09_CODE,
					--(CAST(ceiling(rand() * 19) as int)+1) AS processid,
					@hLotSN_add AS LOT_ID,
					REPLACE(REPLACE(REPLACE(CONVERT(NVARCHAR(20),@lotonsmttime_add,120),'-',''),':',''),' ','') AS lotonsmttime,
					@abside_4d_add,@lotonsmt_userid_add
					FROM dbo.POItemLot WITH (NOLOCK)
					INNER JOIN dbo.POItem WITH (NOLOCK) ON POItem.POItemId = POItemLot.POItemId
					INNER JOIN dbo.PO WITH (NOLOCK) ON PO.POId = POItem.POId
					INNER JOIN dbo.Vendor WITH (NOLOCK) ON Vendor.VendorId = PO.VendorId
					INNER JOIN dbo.ProductRoot WITH (NOLOCK) ON DefaultProductId = POItem.ProductID
					INNER JOIN   dbo.Client  WITH  (NOLOCK) ON  client.ClientSN=POItemLot.ClientSN
					WHERE LotSN = @hProductLotSN_add

					
				
					
	

				------------------------------------------------------------------------------------------------
					SET @ih_add=@ih_add+1
				END
				UPDATE  @Detail_add   SET  SN09_CODE='N/A'  WHERE SN09_CODE='' OR  SN09_CODE IS  NULL	
				UPDATE  @Detail_add   SET  SUPPLIER_CODE='N/A'  WHERE SUPPLIER_CODE='' OR  SUPPLIER_CODE IS  NULL
				UPDATE  @Detail_add   SET  LOTE_CODE='N/A'  WHERE LOTE_CODE='' OR  LOTE_CODE IS  NULL	
				INSERT INTO [10.2.0.8].HWTPW.dbo.IINVLOTHIS_TPW
				( MOVE_FLAG ,
				MOVE_TIME ,
				FACTORY ,
				EMS_ORDER_ID ,
				RAW_MAT_ID ,
				HW_RAW_MAT_ID ,
				RAW_LOT_ID ,
				LINE_ID ,
				UNIT_1 ,
				QTY ,

				SUPPLIER_CODE ,
				SUPPLIER_NAME ,
				LOT_CODE ,
				RAW_MAT_CREATE_TIME ,
				LOT_ID ,

				USE_QTY ,
				SMT_FLAG ,
				SN09_CODE ,
				TRAN_TIME ,
				SERIAL_ID ,

				BT ,
				HW_MAT_ID ,
				MAT_MODEL ,
				RAW_OPER ,
				RAW_LOT_TYPE ,

				-- MAT_VER ,
				TRAN_CODE ,
				TRAN_USER_ID ,
				GETFLAG ,
				GETTIME ,
				ACTIONFLAG
				--SEGMENT1 ,
				--SEGMENT2 ,
				--SEGMENT3 ,
				--SEGMENT4 ,
				--SEGMENT5 ,
				--SEGMENT6 ,
				--SEGMENT7
				)
				SELECT
				'N' , -- MOVE_FLAG - char(1)
				@nowtime4d  , -- MOVE_TIME - nvarchar(14)
				N'ZHUOYI' , -- FACTORY - nvarchar(10)
				--'N' , -- RETURN_FLAG - char(1)
				@moname , -- EMS_ORDER_ID - nvarchar(25)
				RAW_MAT_ID , -- RAW_MAT_ID - nvarchar(30)
				HW_RAW_MAT_ID , -- HW_RAW_MAT_ID - nvarchar(30)
				--N'NA' , -- OLD_RAW_LOT_ID - nvarchar(128)
				RAW_LOT_ID, -- RAW_LOT_ID - nvarchar(128)
				LINE , -- LINE - nvarchar(20)
				N'PCS' , -- UNIT - nvarchar(16)
				QTY , -- QTY - decimal

				--N'NA' , -- SUPPLIER_RAW_MAT_CODE - nvarchar(128)
				SUPPLIER_CODE , -- SUPPLIER_CODE - nvarchar(64)
				SUPPLIER_NAME , -- SUPPLIER_NAME - nvarchar(64)
				--STOCK_IN_TIME , -- STOCK_IN_TIME - nvarchar(14)
				LOTE_CODE , -- LOTE_CODE - nvarchar(64)
				RAW_MAT_CREATE_TIME , -- RAW_MAT_CREATE_TIME - nvarchar(64)
				LOT_ID , -- LOT_ID - nvarchar(64)


				USE_QTY , -- USE_QTY - nvarchar(64)
				'Y' , -- SMT_FLAG - char(1)
				ISNULL(SN09_CODE, 'N/A' ) , -- SN09_CODE - nvarchar(64)
				lotonsmttime,  --TRAN_TIME 物料关联时间
				' ' ,  --SERIAL_ID

				'B' , -- BT ,
				@custmodel_add,--HW_MAT_ID 0302,
				' ',-- MAT_MODEL HG630 ,
				' ' ,       -- RAW_OPER ,
				' ' ,      -- RAW_LOT_TYPE ,


				--' ' ,--MAT_VER ,
				'ONWIP',-- TRAN_CODE ,
				@lotonsmt_userid_add,-- TRAN_USER_ID ,
				0 ,
				@nowtime4d ,
				'I'		
			  FROM @detail_add						
		END
		--================================================================================================================== 2017.06.23


	



--INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SMTIssueExeNew_in','23-8')-- add 20150123
    --insert into CatchErooeLog (ProcName,ErooeCommad ) values('star6-5', @lotsn )
   exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output,
    @LotSNList=@LotSNList,  @SP='Txn_SMTIssueExeNew' ,@Status=0 --标注此批SN已处理完成

   ----统计产出--------
    DECLARE  @DATE_4D  DATETIME=GETDATE()
    EXEC Txn_smtTiePian_chanchu_4d
	@I_ResourceId = @I_ResourceId,		--资源ID(如果资源不在资源清单中，那么它将是空的)
	@I_ResourceName=@I_ResourceName,
	@flag =1, ---1  普通连扳  2板边
	@LotId = @LotId, -- char(12)
	@MOId = @MOId, -- char(12)
	@WorkcenterId = @WorkcenterId, -- char(12)
	@SpecificationId = @SpecificationId, -- char(12)
	@ShiftId = '', -- char(12)
	@DateTime = @DATE_4D
   ----统计产出--------


	BEGIN TRY
		EXEC dbo.Txn_IntervalStaticOfTP 
			@LotId = @IntervalotId, -- char(12)
		    @ResourceId = @I_ResourceId -- char(12)	
	END TRY
	BEGIN CATCH
		PRINT ERROR_MESSAGE()
	END CATCH 
	--INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SMTIssueExeNew_in','23-9')-- add 20150123
   -- INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_SMTIssueExeNew_out','call end')-- add by Wangbo 20141018
    
    SET  @I_ReturnMessage='ServerMessage:批号【'+@LotSN+'】贴片成功!  '
	SELECT  0 AS I_ReturnValue,@I_ReturnMessage as I_ReturnMessage
	
-- add by ybj 20150713
 IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName, ErooeCommad, Duration) values('Txn_SMTIssueExeNew_debug_11', @debug  , DATEDIFF( SECOND, @time, GETDATE() ) )

	RETURN 0 
END