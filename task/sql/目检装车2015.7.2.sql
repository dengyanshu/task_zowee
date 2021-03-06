USE [OrBitX]
GO
/****** Object:  StoredProcedure [dbo].[Txn_DataChainLoadCar]    Script Date: 07/02/2015 17:06:02 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		<MES Team ChenZH>
-- Create date: <2013.12.18>
-- Description:	<SMT装车及外观检查_Batch>
-- 可以重复装车前题是要装车的单板是被PQC 批退的
-- Rev: 10.00 
-- =============================================
ALTER PROCEDURE [dbo].[Txn_DataChainLoadCar]
@I_Sender				nvarchar(200)='',			--客户端执行按钮
@I_ReturnMessage		nvarchar(max)='' output,	--返回的信息,支持多语言
@I_ExceptionFieldName	nvarchar(100)='' output,	--向客户端报告引起冲突的字段
@I_LanguageId			char(1)='1',				--客户端传入的语言ID
@I_PlugInCommand		varchar(5)='',				--插件命令
@I_OrBitUserId			char(12)='',				--用户ID
@I_OrBitUserName		nvarchar(100)='',			--用户名
@I_ResourceId			char(12)='',				--资源ID(如果资源不在资源清单中，那么它将是空的)
@I_ResourceName			nvarchar(100)='',			--资源名
@I_PKId					char(12) = '',				--主键
@I_SourcePKId			char(12)='',				--执行拷贝时传入的源主键  
@I_ParentPKId			char(12)='',				--父级主键
@I_Parameter			nvarchar(100)='',			--插件参数	

@LotSN					nvarchar(50)='',
@CarInfo				nvarchar(50)='',
@MOID					char(12) = '',
@Moname					nvarchar(50) = '',
@DefectcodeSn			nvarchar(50)='' 
as
begin
	SET NOCOUNT ON;
	SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	--变量申明
	declare @LotId				char(12)
	declare @TxnCode			varchar(10)
	declare @Qty				float
	declare @LotStatus			char(1)
	declare @InDate				datetime
	declare @ShiftId			varchar(12)=''
	declare @UserComment		varchar(1000)=''

	declare @sSpecificationId	char(12)
	declare @WorkflowStepId		char(12)
	declare @WorkcenterId		char(12)
	declare @OldShiftId			char(12)=''
	declare @ProductId			char(12)
	declare @MMOID				char(12)
	declare @return_value		int
	DECLARE @ProductionLot		NVARCHAR(50) = ''
	Declare @MOSMTPath			nvarchar(10)
	Declare @WorkflowID			char(12)
	
	
	DECLARE @IsLock				BIT
	DECLARE @SpecificationName	NVARCHAR(50)
	Declare @ErroLotsn			nvarchar(50)	--不在当前站点的LOTSN	
	declare @DataChainId		char(12)
	declare @DataChainLoadCarId char(12)
	DECLARE @RealMoname			NVARCHAR(50)	--lot表中绑定的工单
	
	DECLARE @debug NVARCHAR(50) 
	SET @debug = @LotSN
	DECLARE @if_debug BIT ='false'
	DECLARE @debugtime  TIME= GETDATE();

	
	-- add by ybj 20150127
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_1', @debug   )
	
	
	if @LotSN='+submit+'
	begin
		 if  not exists( select top 1 carsn from  DataChainLoadCar with(nolock)  where CarSN=ISNULL( @CarInfo,'N/A') and MOID=@MOID )
			begin
				set @I_ExceptionFieldName='CarInfo'	
				set @I_ReturnMessage='ServerMessage:此车辆还没装车信息所以不能关闭此车!'+@CarInfo
				return -1
			end
		 if exists( select top 1 lot.LotId from  DataChainLoadCar dlc with(nolock)  --2014.05.27 chenzh限制要关车号车内单品必须全在IPQC节点,以防用错程序
					inner join lot with(nolock) on lot.LotId=dlc.LotID
					where CarSN=ISNULL( @CarInfo,'N/A') and dlc.MOID=@MOID and lot.SpecificationId<>'SPE10000004R' )
			begin
				set @I_ExceptionFieldName='CarInfo'	
				set @I_ReturnMessage='ServerMessage:当前车节点不正确不能关闭此车请检查是否用错程序!'+@CarInfo
				return -1
			end
		
		UPDATE moitemlot SET moitemlot.BrandStatus='1' WHERE LotSN= @CarInfo and MOId=@MOID -- CHENZH 2013.10.08 添加
		set @I_ExceptionFieldName='CarInfo'	
				set @I_ReturnMessage='ServerMessage:车辆关闭成功!'+@CarInfo
				return 0
	end
	
	IF  EXISTS(SELECT UserCodeName FROM UserCode WHERE UserCodeName = @LotSN and UserCode.ParentUserCodeId in ( 'URC1000005SM','URC1000006M3') ) --如果当前批号输入的是不良代码则把不良代码反回界面
	begin
		SET @I_ExceptionFieldName = 'LotSN'
		select  ISNULL(@LotSN,'N/A') DefectcodeSn	--
		--INSERT INTO  CatchErooeLog(ProcName,ErooeCommad) VALUES('Txn_DataChainLoadCar',@LotSN)
		RETURN 0
	end
	
	select  @ProductionLot=ProductionLot from lot where LotSN=@LotSN
	if ISNULL(@ProductionLot,'')=''
	begin
		set @I_ReturnMessage='ServerMessage:此板不存在连板信息!'+@LotSN
		return -1
	END
	DECLARE @BadSN NVARCHAR(100)
	
	select top 1  @BadSN=LotSN from lot WHERE ProductionLot=@ProductionLot and LotStatus='R'      --2014-10-21  dali
	IF ISNULL(@BadSN,'')<>''
	BEGIN
		set @I_ReturnMessage='ServerMessage:此连板存在批号['+@BadSN+']目前正处于在线维修中'
		--select  '00000' DefectcodeSn ,@I_ReturnMessage I_ReturnMessage, -1 I_ReturnValue
		return -1
	end
		
	
		-- add by ybj 20150127
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_2', @debug   )
	--IF EXISTS(SELECT dbo.DataChainSMTVisualInspection.LotSN FROM DataChainSMTVisualInspection           
	-- INNER JOIN lot ON dbo.DataChainSMTVisualInspection.LotID = dbo.Lot.LotId
	--WHERE DefectcodeSn<>'00000' AND ISNULL(DefectcodeSn,'')<>''AND ProductionLot=@ProductionLot)
	--BEGIN
	--DECLARE @BadSN NVARCHAR(100)
	--SELECT @BadSN=dbo.DataChainSMTVisualInspection.LotSN FROM DataChainSMTVisualInspection INNER JOIN lot ON dbo.DataChainSMTVisualInspection.LotID = dbo.Lot.LotId
	--WHERE DefectcodeSn<>'00000' AND ISNULL(DefectcodeSn,'')<>''AND ProductionLot=@ProductionLot 
	--set @I_ReturnMessage='ServerMessage:此板所在的连板存在不良板!'+@BadSN
	----return -1
	--END
	
	
		---新增校验是否抛料
	DECLARE @sntype NVARCHAR(50)
	DECLARE @MakeUpCount int
	SELECT @MakeUpCount=MakeUpCount,@LotId=LotId FROM lot WHERE LotSN=@lotsn
	SELECT @sntype=SNType FROM dbo.MOItemLot WHERE moid=@moid AND LotSN=@LotSN
	DECLARE @lotqty INT 
	SELECT @lotqty=COUNT(*) FROM lot WHERE ProductionLot=@ProductionLot
	
	IF	 @sntype<>'SN' AND @MakeUpCount>@lotqty
	BEGIN
		set @I_ReturnMessage='ServerMessage:此批号['+@LotSN+']抛料。请执行抛料处理程序!数据连板数为:'+CONVERT(NVARCHAR(50),@MakeUpCount)
		return 1
	END
	
	DECLARE @CustomerId CHAR(12)
	DECLARE @WOSN NVARCHAR(50)
	DECLARE @IsHuaWeiCustomer BIT
	SELECT @CustomerId=MO.CustomerId,@WOSN=MO.WOSN FROM dbo.MO WITH(NOLOCK) WHERE MOId=@MOID
    BEGIN
		EXEC dbo.txn_IsHuaWeiCustomer 
				@CustomerId = @CustomerId, -- char(12)
				@MOID=@MOID,
				@IsHuaWeiCustomer = @IsHuaWeiCustomer OUTPUT -- bit
    END 
	-------------------------------------------------------------------------------------------
	if isnull(@DefectcodeSn,'')<>'' and isnull(@DefectcodeSn,'')<>'00000'  --发现不良
	begin
		
		--- 识别是否是华技客户的工单	20140823
		
		select @customerID= p.CustomerId from mo join product p on mo.ProductId= p.ProductId where MOid=@MOID
		--select * from Customer where CustomerId =@customerID

		if  @CustomerId in('CUS1000000J4','CUS1000000QL'  ) --识别是否是华技客户的工单
		begin
			--declare @DefectCodeId char(20)
			--SELECT TOP 1 @DefectCodeId=UserCodeId FROM dbo.UserCode WHERE UserCodeName=@DefectcodeSn AND ParentUsercodeID = 'URC1000006M3' 
			--IF ISNULL(@DefectCodeId,'N/A')='' or ISNULL(@DefectCodeId,'N/A')='N/A'
			
			IF NOT EXISTS( SELECT TOP 1 UserCodeName FROM dbo.UserCode WHERE UserCodeName=@DefectcodeSn AND ParentUsercodeID = 'URC1000006M3'  ) --华技缺陷代码			
			BEGIN
				set @I_ExceptionFieldName='DefectcodeSn'
				set @I_ReturnMessage='ServerMessage:此不良代码：'+ISNULL(@DefectcodeSn,'N/A') + '不是华技不良代码。'
				--select 'ServerMessage:系统中不存在此不良代码：'
				return -1
			END
		end 
		else
		begin			
			IF NOT EXISTS(SELECT UserCodeName FROM UserCode WHERE UserCodeName = @DefectcodeSn and UserCode.ParentUserCodeId in('URC1000005SM') ) --SMT-PIQC不良代码
			BEGIN
				SET @I_ExceptionFieldName = 'DefectcodeSn'
				SET @I_ReturnMessage = 'ServerMessage:不良代码在[SMT-PIQC不良代码]中不存在,请确认后再扫描.'
				RETURN -1
			END	
		end					
		--- ---------------
		
		-- add by ybj 20150127
      IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_3', @debug   )	
		
		
		select top 1  @ErroLotsn=LotSN ,@SSPecificationid = SpecificationID,@WorkflowStepId=WorkflowStepId 
		from lot WHERE ProductionLot=@ProductionLot AND  ISNULL(SpecificationId,'')<>'SPE10000004Q'  
		IF ISNULL(@ErroLotsn,'') <> ''
		BEGIN
			set @I_ExceptionFieldName = 'LotSN'
			--SELECT TOP 1 @SpecificationName=SpecificationName  FROM dbo.SpecificationRoot WHERE DefaultSpecificationId=@SSPecificationid
			SELECT @SpecificationName=WorkflowStepName FROM dbo.WorkflowStep WHERE WorkflowStepId=@WorkflowStepId
			set @I_ReturnMessage='ServerMessage:(ERROBB)此批号'+@ErroLotsn+'不在此装车工位,目前所在工站：['+ISNULL(@SpecificationName,'N/A')+']'
			return -1
		END
		
		--declare  @body nvarchar(100)
		--set @body='lotsn:'+@LotSN+',不良代码:'+isnull(@DefectcodeSn,'n/a')
		--exec [Send_Mail1--gh] 
		--	@recipients ='chenzh@zowee.com.cn'
		--	,@copy_recipients=''
		--	,@subject='装车录入不良代码(Txn_DataChainLoadCar)',
		--	@body=@body
		
		exec SysGetObjectPKid '','DataChainLoadCar',@DataChainLoadCarId  output
		insert into DataChainLoadCar  (
							DataChainLoadCarID,
							LotId,
							LotSN,			
							--CarSN,
							MOID,
							UserID,
							NSStatus,
							ProdentryStatus,
							CreateDate,
							DefectcodeSn,
							
							ResourceId
							)
						Values  (
							@DataChainLoadCarId,
							@LotId,
							@LotSN,
							--@CarInfo,
							@MOID,
							@I_OrBitUserId,
							'',
							'',
							Getdate(),
							@DefectcodeSn,
							
							@I_ResourceId
							)
							
		
		DECLARE @ProductionLot11 NVARCHAR(50)
		select @ProductionLot11=ProductionLot from lot where LotSN=@LotSN and LotStatus='1'
		--update lot set LotStatus='R' from lot where ProductionLot=@ProductionLot11 
		update lot set LotStatus='R' from lot where lotsn=@LotSN  --qinyp 2014-10-27
		IF @IsHuaWeiCustomer='true' --如果是华为客户,上传记录到华为表
		 BEGIN
			DECLARE @ss NVARCHAR(50)
			DECLARE tempCur CURSOR
			FOR
			--SELECT LotSN FROM dbo.Lot  WITH(NOLOCK) WHERE ProductionLot=@ProductionLot11
			SELECT LotSN FROM dbo.Lot  WITH(NOLOCK) WHERE lotsn=@LotSN  -- qinyp 2014-10-27
			OPEN tempCur
			FETCH NEXT FROM tempCur INTO @ss
			WHILE @@fetch_status =0
			 BEGIN
				BEGIN TRY
					EXEC dbo.Interface_HuaWei_IWIPLOTSTS 
					@I_ReturnMessage=@I_ReturnMessage OUTPUT,
					@LOT_ID=@ss,
					@EMS_ORDER_ID=@MOName,
					@PASS_FAIL_FLAG='F',
					@DEFECT_CODE=@DefectcodeSn			--不良代码(如果有的话)
				END TRY
				BEGIN CATCH
				    INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_Huawei',ISNULL(ERROR_MESSAGE(),'上传到华为记录表中失败')+ ' ' + ISNULL(@I_ReturnMessage,'')) -- add by ybj 20141016
					PRINT ERROR_MESSAGE()
				END CATCH 
				FETCH NEXT FROM tempCur INTO @ss
			 END
			CLOSE  tempCur
			DEALLOCATE tempCur
		 END					
		
		-- add by ybj 20150127
      IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_4', @debug   )	
		SET @I_ExceptionFieldName = 'LotSN'
		select  ' ' DefectcodeSn	--清空不良代码
		SET @I_ReturnMessage = 'ServerMessage: 条码 '+@LotSN+' 已标记为维修状态'
		RETURN 0
	end
	-----------------------------------------------------------------------------------
	declare @TbLot table
	(	
		RowNum			int,
		LotId			nchar(12),
		LotSn			nvarchar(50),
		MoId			nchar(12),
		LotStatus		char(2),
		IsLock			bit,
		SpecificationId	nchar(12),
		WorkflowID		nchar(12),
		WorkflowStepId	nchar(12),
		ProductionLot	nvarchar(50),
		DataChainId		nchar(12),
		
		ResourceId nchar(12)
	)
	insert into @TbLot select 
		ROW_NUMBER() OVER (ORDER BY LotId) AS RowNum,
		LotId,			
		LotSn,		
		MoId,			
		LotStatus,		
		IsLock,
		SpecificationId,	
		WorkflowID,		
		WorkflowStepId,	
		ProductionLot,
		null	,
		
		lot.ResourceId
	from lot where 
		ProductionLot=@ProductionLot and LotSN<>@ProductionLot
	if not exists( select top 1 lotid  from @TbLot)
	BEGIN
		set @I_ExceptionFieldName = 'LotSN'
		set @I_ReturnMessage='ServerMessage: Lot is not existed'
		return -1
	end
	if  exists(select top 1 lotid  from @TbLot where MoId<>@MOID)
	BEGIN
		set @I_ExceptionFieldName = 'Moname'
		select @RealMoname=MOName from mo where MOId=(select top 1 MOId from @TbLot where MoId<>@MOID)
		set @I_ReturnMessage='ServerMessage:批号工单与所选工单不符，请检查!'+ ISNULL(@Moname,'') + '----此板属于工单:  ' + ISNULL(@RealMoname,'')
			+ '------' + ISNULL(@LotSN,'')
		return -1
	end
	select top 1  @ErroLotsn=LotSN ,@SSPecificationid = SpecificationID,@WorkflowStepId=WorkflowStepId from @TbLot where  SpecificationId<>'SPE10000004Q' 
	IF ISNULL(@ErroLotsn,'') <> ''
	BEGIN
		set @I_ExceptionFieldName = 'LotSN'
		--SELECT TOP 1 @SpecificationName=SpecificationName  FROM dbo.SpecificationRoot WHERE DefaultSpecificationId=@SSPecificationid
		SELECT @SpecificationName=WorkflowStepName FROM dbo.WorkflowStep WHERE WorkflowStepId=@WorkflowStepId
		set @I_ReturnMessage='ServerMessage:(ERRO)此连板存在批号'+@ErroLotsn+'不在此装车工位,目前所在工站：['+ISNULL(@SpecificationName,'N/A')+']'
		return -1
	END
	
	select top 1  @LotStatus=LotStatus , @ErroLotsn=LotSN from @TbLot where LotStatus='R'	--2013.11.27 陈宗海 添加
	if isnull(@LotStatus,'')<>''
	BEGIN
		set @I_ExceptionFieldName = 'LotSN'
		set @I_ReturnMessage='ServerMessage:此连板存在批号['+@ErroLotsn+']目前正处于在线维修中'
		return -1
	end
	--if isnull(@DefectcodeSn,'')<>'' --发现不良
	--begin
	--	IF NOT EXISTS(SELECT UserCodeName FROM UserCode WHERE UserCodeName = @DefectcodeSn and UserCode.ParentUserCodeId='URC1000005SM' ) --SMT-PIQC不良代码
	--	BEGIN
	--		SET @I_ExceptionFieldName = 'DefectcodeSn'
	--		SET @I_ReturnMessage = 'ServerMessage:不良代码不存在,请确认后再扫描.'
	--		RETURN -1
	--	END	
	--	exec SysGetObjectPKid '','DataChainLoadCar',@DataChainLoadCarId  output
	--	insert into DataChainLoadCar  (
	--						DataChainLoadCarID,
	--						LotId,
	--						LotSN,			
	--						CarSN,
	--						MOID,
	--						UserID,
	--						NSStatus,
	--						ProdentryStatus,
	--						CreateDate,
	--						DefectcodeSn
	--						)
	--					Values  (
	--						@DataChainLoadCarId,
	--						@LotId,
	--						@LotSN,
	--						@CarInfo,
	--						@MOID,
	--						@I_OrBitUserId,
	--						'',
	--						'',
	--						Getdate(),
	--						@DefectcodeSn)
	--	update lot set LotStatus='R' from lot inner join @TbLot tblot on lot.LotId=tblot.LotId where tblot.LotStatus=1
	--	SET @I_ExceptionFieldName = 'LotSN'
	--	select  '' DefectcodeSn	--清空不良代码
	--	SET @I_ReturnMessage = 'ServerMessage: 条码 '+@LotSN+' 关连的连板条码已标记为维修状态'
	--	RETURN 0
	--end
	--IF  EXISTS(SELECT UserCodeName FROM UserCode WHERE UserCodeName = @LotSN and UserCode.ParentUserCodeId='URC1000005SM' ) --如果当前批号输入的是不良代码则把不良代码反回界面
	--begin
	--	SET @I_ExceptionFieldName = 'LotSN'
	--	select  @LotSN DefectcodeSn	--清空不良代码
	--	RETURN 0
	--end
	
	--检查车辆是否已扫描
	if isnull(@CarInfo,'')=''
	begin
		set @I_ExceptionFieldName='CarInfo'	
		set @I_ReturnMessage='ServerMessage:车辆信息没扫描,请先扫描车辆!'
		return -1
	end
	
	declare @myCarSN varchar(50)
	select @myCarSN = CarSN from DataChainLoadCar where LotSN = @LotSN and DefectcodeSn is null and isnull(QCCheckresult,1)<>0
	if Isnull(@myCarSN,'')<>'' --and (@myCarSN != @CarInfo)  -- 陈宗海 2013.12.13 把Isnull(@myCarSN,'')='' 改为Isnull(@myCarSN,'')<>''
	begin
		
		set @I_ReturnMessage='ServerMessage: ' + ISNULL(@LotSN,'') + ' 已经装在:' + ISNULL(@myCarSN,'')
		return -1
	end
	
    --判断车号是否正确
    if not exists(select top 1 moitemlot.LotSN from moitemlot where SNTYPE='CartonSN' and MOId=@MOID and  isnull(BrandStatus,'')='' and LotSN=@CarInfo )
	begin
		set @I_ExceptionFieldName='CarInfo'	
		declare @BrandStatus nvarchar(10)
		SET @Moname=''
		select @Moname =MOName,@BrandStatus=moitemlot.BrandStatus from mo inner join moitemlot on mo.MOId=moitemlot.MOId where moitemlot.LotSN=@CarInfo
		if ISNULL(@Moname,'')<>''
		begin
			if ISNULL(@BrandStatus,'')<>''
				set @I_ReturnMessage='ServerMessage:车辆信息:['+@CarInfo+'],已装车完毕不能再使用 '	
			else
				set @I_ReturnMessage='ServerMessage:车辆信息:['+@CarInfo+'],属于工单 ['+@Moname+']'
		end
		ELSE
			set @I_ReturnMessage='ServerMessage:车辆信息:'+@CarInfo+',不存在 '		
		return -1
	end
	select @I_ResourceId=ResourceId,@WorkcenterId=WorkcenterId from Resource where ResourceName=@I_ResourceName --取资源ID,工作中心ID
	
	IF exists(select *  from DataChainLoadCar where CarSN=isnull(@CarInfo,'N/A') and ProdentryStatus  is   null )
	BEGIN
		set @I_ExceptionFieldName = 'LotSN'
		set @I_ReturnMessage='ServerMessage:此车号已装有板边条码正常板，不能再装正常装车节点的单板！！['+isnull(@CarInfo,'N/A')+']'
		return -1
 	end
	IF exists(select top 1 lotid from @TbLot where isnull(IsLock,'false')='true')
	BEGIN
		set @I_ExceptionFieldName = 'LotSN'
		set @I_ReturnMessage='ServerMessage:此批号已被锁定,请检查!'
		return -1
	END
	 declare @returnvalues int
	declare @LotSNList nvarchar(max)
	set @LotSNList=(select top 1 LotSn+',' from @TbLot for xml path(''))
	exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList ,@Status=1 --标注此批SN正在处理 
	if @returnvalues=-1
	begin
		return -1
	end
	
	declare @i int=1
	declare @j int =0
	select @j=COUNT (lotid) from @TbLot 
	set @TxnCode='DC'
	set @InDate=GETDATE()
	while @i<=@j
	begin
		select @LotId=lotid,@LotSN=lotsn,@WorkflowStepId=tblot.WorkflowStepId from @TbLot tblot where RowNum=@i
	
		EXEC	[dbo].[TxnBase_DataChainMainLine]
			@DataChainId = @DataChainId OUTPUT,
			@TxnCode =@TxnCode,
			@I_PlugInCommand = @I_PlugInCommand,
			@I_OrBitUserId = @I_OrBitUserId,
			@I_ResourceId = @I_ResourceId,
			@LotId = @LotId,
			@ProductId = @ProductId,
			@Qty = @Qty,
			@WorkcenterId = @WorkcenterId,
			@WorkflowStepId = @WorkflowStepId,
			@MOID=@MOID,
			@UserComment='正常装车'
		update @TbLot set DataChainId=@DataChainId where  RowNum=@i
		
		--IF @LotSN BETWEEN '8S0062010745ZY603690001' AND '8S0062010745ZY60369198L'
		--BEGIN
		--	DECLARE @Date DATETIME
		--	SET @Date=GETDATE()
		--	EXEC	@return_value = [dbo].[TxnBase_LotNonStdMove] --传送到指定节点
		--		@I_ReturnMessage = @I_ReturnMessage OUTPUT,
		--		@I_PlugInCommand = @I_PlugInCommand,
		--		@I_OrBitUserId = @I_OrBitUserId,
		--		@I_ResourceId =  @I_ResourceId,
		--		@LotSN =@LotSN,
		--		@LotInDate = @Date,
		--		@ShiftId = @ShiftId,
		--		--@NonStdMoveReasonId = @NonStdMoveReasonId,
		--		@TargetWorkflowId = @WorkflowId ,
		--		@TargetWorkflowStepId = 'WFS10000035Q',
		--		@UserComment = @UserComment
		--END
				
		EXEC	@return_value = [dbo].[TxnBase_LotMove]
					@I_ReturnMessage = @I_ReturnMessage OUTPUT,
					@I_PlugInCommand = @I_PlugInCommand,
					@I_OrBitUserId = @I_OrBitUserId,
					@I_ResourceId = @I_ResourceId,
					@I_ResourceName = @I_ResourceName,
					@LotSN = @LotSN,
					@LotInDate = @InDate,
					@ShiftId = @ShiftId,
					@UserComment = @UserComment
					
		--IF @IsHuaWeiCustomer='true' --如果是华为客户,上传记录到华为表    --20140917 chenzh	把插入华为数据库动作放在装车成功之后
		-- BEGIN
		--	EXEC dbo.Interface_HuaWei_IWIPLOTSTS 
		--	@I_ReturnMessage=@I_ReturnMessage OUTPUT,
		--	@LOT_ID=@LotSN,
		--	@EMS_ORDER_ID=@MOName,
		--	@PASS_FAIL_FLAG='P',
		--	@DEFECT_CODE=NULL			--不良代码(如果有的话)
		-- END
		set @i+=1
	end   
	
	------------- 整体移动过站
	--declare @ListLotSN nvarchar(max)=''
	--	set @ListLotSN=(select lotsn +',' from @TbLot for xml path('') ) 
	--	EXEC	[dbo].[TxnBase_LotMove_Batch]
	--				@I_ReturnMessage = @I_ReturnMessage OUTPUT,
	--				@I_PlugInCommand = @I_PlugInCommand,
	--				@I_OrBitUserId = @I_OrBitUserId,
	--				@I_ResourceId = @I_ResourceId,
	--				@ListLotSN = @ListLotSN
	
	declare  @PKDataSet  table  ( --主键表用以保存指定表的主键ID
				RowNum int,
				PkID char(12)
				)	
	insert into @PKDataSet 
	EXEC SysGetBatchObjectPKId @ObjectName='DataChainLoadCar' ,@RowCount=@j --取指定数量的DataChainLoadCar表主键id

	insert into DataChainLoadCar  (
			DataChainLoadCarID,
			DataChainId,
			LotId,
			LotSN,			
			CarSN,
			MOID,
			UserID,
			NSStatus,
			ProdentryStatus,
			CreateDate, 
			
			ResourceId
			)
			select 
			pk.PkID,
			tbLot.DataChainId,
			tbLot.LotId,
			tbLot.LotSn,
			@CarInfo,
			tbLot.MoId,
			@I_OrBitUserId,
			'',
			'',
			Getdate(),
			
			ResourceId
			from @TbLot tbLot 
			inner join @PKDataSet pk on tbLot.RowNum=pk.RowNum
	
	
	-------------
	--第一次装车的过站数
	declare @DateTime datetime
 	declare @tCount		int	--装车数
	DECLARE @CreateDate DATE
	DECLARE @TimeSlice INT
	declare @SpecificationId nchar(12)
	
	select @tCount=COUNT(*) from @TbLot t
	left join DataChainLoadCar dcc with(nolock)
	on t.lotid=dcc.lotid
	where DefectcodeSn is null and dcc.LotID is null --取当前板没装过车的数量
	
	set @tCount =ISNULL(@tCount,0)
	 SET @DateTime=ISNULL(@DateTime,GETDATE())
	
		set @ShiftId=''
		IF ISNULL(@ShiftId,'')=''
		 BEGIN
			EXEC dbo.txn_GetShiftId
				 @DateTime=@DateTime,
				 @ShiftId = @ShiftId OUTPUT -- char(12)
		 END
		
		EXEC dbo.Proc_SpecificationStatisticsTimeSlice
			@StatisticsDateTime =@DateTime, -- datetime
			@Date = @CreateDate OUTPUT, -- date
			@TimeSlice = @TimeSlice OUTPUT-- int 
		    
		SET @LotId=ISNULL(@LotId,'')
		SET @MOId=ISNULL(@MOId,'') 
		SET @WorkcenterId=ISNULL(@WorkcenterId,'')
		SET @SpecificationId='SPE10000004Q'
		SET @ShiftId=ISNULL(@ShiftId,'')
		SET @TimeSlice=ISNULL(@TimeSlice,-1)
		SET @CreateDate=ISNULL(@CreateDate,GETDATE())
		
	IF EXISTS(SELECT 1 FROM dbo.Base_Statistics  WITH(NOLOCK) 
			WHERE CreateDate=@CreateDate
			AND TimeSlice=@TimeSlice
			AND MOId=@MOId
			AND WorkcenterId=@WorkcenterId
			AND ShiftId=@ShiftId
			AND SpecificationId=@SpecificationId)
		 BEGIN
			UPDATE Base_Statistics SET Qty=ISNULL(Qty,0)+@tCount
			WHERE CreateDate=@CreateDate
			AND TimeSlice=@TimeSlice
			AND MOId=@MOId
			AND WorkcenterId=@WorkcenterId
			AND ShiftId=@ShiftId
			AND SpecificationId=@SpecificationId
		 END
		ELSE
		 BEGIN
			INSERT INTO dbo.Base_Statistics
					( CreateDate ,
					  TimeSlice ,
					  MOId ,
					  WorkcenterId ,
					  ShiftId ,
					  SpecificationId ,
					  Qty
					)
			VALUES  ( @CreateDate , -- CreateDate - date
					  @TimeSlice , -- TimeSlice - int
					  @MOId , -- MOId - char(12)
					  @WorkcenterId , -- WorkcenterId - char(12)
					  @ShiftId , -- ShiftId - char(12)
					  @SpecificationId , -- SpecificationId - char(12)
					  @tCount  -- Qty - bigint
					)
		 END	
	------------------------
	
	-- add by ybj 20150127
   IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_5', @debug   )
	
	Declare @CountCar int
	select @CountCar = COUNT(datachainloadCarID) from DataChainLoadCar WITH(NOLOCK)
		where MOID = @MOID and CarSN = @CarInfo and Isnull(NSStatus,'') <> 'NS' and isnull(ProdentryStatus,'') <> '1'
		AND DataChainLoadCar.DefectcodeSn IS NULL 
	set @I_ReturnMessage='ServerMessage:数据采集成功！装车完毕，已装车数量：' +CAST(@CountCar as varchar(10))
	
	exec @returnvalues=Proc_RegisterDoingSN @I_ReturnMessage=@I_ReturnMessage output, @LotSNList=@LotSNList ,@Status=0 --标注此批SN已处理完成
	
	  IF @if_debug = 'true'
      INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_51', @debug+'/' + CAST( @j AS CHAR(10))  )
      
	set @i=1
	while @i<=@j
	begin
		select @LotId=lotid,@LotSN=lotsn,@WorkflowStepId=tblot.WorkflowStepId from @TbLot tblot where RowNum=@i
		IF @IsHuaWeiCustomer='true' --如果是华为客户,上传记录到华为表
		BEGIN
			EXEC dbo.Interface_HuaWei_IWIPLOTSTS 
			@I_ReturnMessage=@I_ReturnMessage OUTPUT,
			@LOT_ID=@LotSN,
			@EMS_ORDER_ID=@MOName,
			@PASS_FAIL_FLAG='P',
			@DEFECT_CODE=NULL			--不良代码(如果有的话)
		END
		set @i+=1
	end
	
	set @I_ExceptionFieldName = 'LotSN'
	BEGIN TRY
	IF	@Customerid IN ('CUS1000000J7','CUS1000000MK','CUS1000000OS')
	EXEC TE.dbo.OEM_TBL_SMT_MACHINE_1
	@lotsn=@lotsn
	END TRY
	BEGIN CATCH
	
-- add by ybj 20150127
 IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_6', @debug   )

	RETURN 0
	END  CATCH
	
-- add by ybj 20150127
 IF @if_debug = 'true'
INSERT into CatchErooeLog(ProcName,ErooeCommad) values('Txn_DataChainLoadCar_debug_7', @debug   )
	
	return 0
end
--select * from WorkflowStep where WorkflowStepId='WFS10000035Q'