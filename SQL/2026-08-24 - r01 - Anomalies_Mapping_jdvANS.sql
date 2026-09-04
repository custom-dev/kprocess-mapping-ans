
CREATE OR ALTER PROCEDURE dbo.comparer_mapping_KProcess_ANS
	--@JsonSource = path du fichier jeuxDeValeurs.json
	@JsonSource NVARCHAR(500),
	--@DatabaseName = par exemple : 'OncoPC_DCC_test'
	@DatabaseName SYSNAME

	AS
	BEGIN

		SET NOCOUNT ON;

		DECLARE @NomDeFichierJson AS NVARCHAR (MAX);
		DECLARE @NomDeFichierXml AS NVARCHAR(MAX);
		DECLARE @Json AS NVARCHAR (MAX);
		DECLARE @Profile AS NVARCHAR (MAX);
		DECLARE @Version AS NVARCHAR (MAX);
		DECLARE @Name AS NVARCHAR (500);
		DECLARE @IgnoredValues AS NVARCHAR(MAX);
		DECLARE @MonSql AS NVARCHAR (MAX);
		DECLARE @SqlToMap AS NVARCHAR (MAX);
		DECLARE @SqlToInsert AS NVARCHAR (MAX);
		DECLARE @SqlExtraValues AS NVARCHAR (MAX);
		DECLARE @SqlMoveTo AS NVARCHAR(MAX);
		DECLARE @SqlDoppelganger AS NVARCHAR(MAX);
		DECLARE @Table AS SYSNAME;
		DECLARE @JdvAns AS NVARCHAR (MAX);
		DECLARE @JsonCursor AS NVARCHAR (MAX);
		DECLARE @PathJson AS NVARCHAR (MAX);
		DECLARE @PathJsonfile AS NVARCHAR(MAX);
		DECLARE @PathXml AS NVARCHAR(MAX);
		DECLARE @PathXmlFile AS NVARCHAR(MAX);
		DECLARE @MonXml AS NVARCHAR(MAX);
		DECLARE @XmlTable AS TABLE(nom VARCHAR(250), filename VARCHAR(500), xml NVARCHAR(MAX));
		DECLARE @XmlCursor AS VARCHAR (MAX);

		DROP TABLE IF EXISTS #anomalies;
		CREATE TABLE #anomalies (
			profil              NVARCHAR (MAX),
			version             NVARCHAR (250),
			fichier_json_name   NVARCHAR (MAX),
			name                NVARCHAR (500),
			table_name          SYSNAME       ,
			jeux_de_valeurs_name NVARCHAR (MAX),
			j_kprocess          NVARCHAR (MAX),
			j_code				NVARCHAR (MAX),
			j_code_system		NVARCHAR (MAX),
			j_ignored_values	NVARCHAR (MAX),
			j_additional_values NVARCHAR (MAX),
			k_values		    NVARCHAR (MAX),
			k_code				NVARCHAR (MAX),
			x_code				NVARCHAR (MAX),
			x_code_system		NVARCHAR (MAX),
			is_ignored          BIT DEFAULT 0,
			value_to_map        BIT DEFAULT 0,
			extra_value         BIT DEFAULT 0,
			to_insert           BIT DEFAULT 0, 
			to_delete			BIT DEFAULT 0,
			move_to				NVARCHAR (MAX),
			doppelganger		BIT DEFAULT 0
		);

		-- Table temporaire pour stocker le contenu du XML
		DROP TABLE IF EXISTS #valeurs_xml_ans;
		CREATE TABLE #valeurs_xml_ans (
			x_code        NVARCHAR(250),
			x_code_system NVARCHAR(500)
		);

		-- Acces au JSON jeuxDeValeurs
		SET @MonSql = N'
			DECLARE @JsonBinary VARBINARY(MAX);
			SELECT @JsonBinary = BulkColumn
			FROM OPENROWSET(BULK '''+@JsonSource+''', SINGLE_BLOB) AS source;
			DECLARE @temp TABLE (val VARCHAR(MAX) COLLATE French_100_CI_AS_SC_UTF8);
            INSERT INTO @temp (val) SELECT @JsonBinary;
            SELECT @Json = CONVERT(NVARCHAR(MAX), val) FROM @temp;					
			';

		EXECUTE sp_executesql @MonSql, N'@Json NVARCHAR(MAX) OUTPUT', @Json = @Json OUTPUT;
		
		--Recuperation des valeurs globales du JSON jeuxDeValeurs et du chemin de chaque fichier de mapping
		SELECT @Profile = profil,
			   @Version = version,
			   @PathJson = pathJSON,
			   @PathXml = pathJSON
		FROM OPENJSON (@Json) WITH (
			profil NVARCHAR (MAX) '$.profile',
			version NVARCHAR (MAX) '$.version',
			pathJSON NVARCHAR (MAX) '$.baseDir'
			);

		SET @PathJson = @PathJson + '\Mappings\';

		SET @PathXml = @PathXml + '\JeuxDeValeurs\';
				
		-- Creation de curseur pour naviguer dans chaque fichier XML de l'ANS
		DECLARE foreachANS CURSOR LOCAL FAST_FORWARD
			FOR SELECT fichier
				FROM OPENJSON (@Json, '$.jeuxDeValeursANS') WITH (fichier NVARCHAR (MAX) '$.file');



		OPEN foreachANS;

		FETCH NEXT FROM foreachANS INTO @NomDeFichierXml;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @PathXmlfile = @PathXml + @NomDeFichierXml;
			--Lecture du fichier XML ANS specifique à chaque jeu de valeur
			SET @MonSql = N'
				DECLARE @XmlBinary VARBINARY(MAX);
				SELECT @XmlBinary = BulkColumn
				FROM OPENROWSET(BULK ''' + @PathXmlfile + ''', SINGLE_BLOB) AS sourceXML;
				SELECT @XmlCursor = CONVERT(VARCHAR(MAX), @XmlBinary);		
				';

			PRINT 'Chargement fichier XML ' + @PathXmlFile;
			EXECUTE sp_executesql @MonSql, N'@XmlCursor VARCHAR(MAX) OUTPUT', @XmlCursor = @XmlCursor OUTPUT;			

			WITH XMLNAMESPACES ('urn:ihe:iti:svs:2008' AS ns)
			INSERT INTO @XmlTable(nom, filename) 
			SELECT
				COALESCE(CONVERT(XML, @XmlCursor).value('(/ns:RetrieveValueSetResponse/ns:ValueSet/@name)[1]', 'NVARCHAR(500)'), CONVERT(XML, @XmlCursor).value('(/ns:RetrieveValueSetResponse/ns:ValueSet/@displayName)[1]', 'NVARCHAR(500)')),
				@PathXmlfile
			FETCH NEXT FROM foreachANS INTO @NomDeFichierXml;
			
		END
		

		--Creation de curseur pour naviguer dans chaque fichier json de mapping
		DECLARE foreach CURSOR LOCAL FAST_FORWARD
			FOR SELECT fichier
				FROM OPENJSON (@Json, '$.mappings') WITH (fichier NVARCHAR (MAX) '$.file');

		OPEN foreach;

		FETCH NEXT FROM foreach INTO @NomDeFichierJson;

		WHILE @@FETCH_STATUS = 0
			BEGIN
			
				SET @PathJsonfile = @PathJson + @NomDeFichierJson;
				PRINT 'pathJson : ' + @PathJsonfile;
				--Lecture du fichier JSON specifique à chaque jeu de valeur
				SET @MonSql = N'
					DECLARE @JsonBinary VARBINARY(MAX);
					SELECT @JsonBinary = BulkColumn
					FROM OPENROWSET(BULK ''' + @PathJsonfile + ''', SINGLE_BLOB) AS sourceJSON;
					DECLARE @temp TABLE (val VARCHAR(MAX) COLLATE French_100_CI_AS_SC_UTF8);
                    INSERT INTO @temp (val) SELECT @JsonBinary;
                    SELECT @JsonCursor = CONVERT(NVARCHAR(MAX), val) FROM @temp;		
					';
				EXECUTE sp_executesql @MonSql, N'@JsonCursor NVARCHAR(MAX) OUTPUT', @JsonCursor = @JsonCursor OUTPUT;

				SELECT @nomDeFichierXml = X.filename
					FROM @XmlTable AS X,
						OPENJSON (@JsonCursor) WITH (fichierXML NVARCHAR (MAX) '$.jeuDeValeursANS') AS J
					WHERE X.nom = J.fichierXML
				PRINT 'nomDeFichierXml : '+@nomDeFichierXml; 
				SET @PathXmlFile = @NomDeFichierXml --+ '.xml';
				
				TRUNCATE TABLE #valeurs_xml_ans;

				--Recuperation des données du jeu de valeur XML dans une tableau temporaire #valeurs_xml_ans
				SET @MonXml = N'
					DECLARE @xml XML;
					SELECT @xml = CAST(BulkColumn AS XML)
					FROM OPENROWSET(BULK '''+@PathXmlFile+''', SINGLE_BLOB) AS sourceXML;
					WITH XMLNAMESPACES (''urn:ihe:iti:svs:2008'' AS ns)
					INSERT INTO #valeurs_xml_ans (x_code, x_code_system)
					SELECT
						concept.value(''@code'',        ''NVARCHAR(250)'')    AS x_code,
						concept.value(''@codeSystem'', ''NVARCHAR(500)'')  AS x_code_system
					FROM @xml.nodes(''/ns:RetrieveValueSetResponse/ns:ValueSet/ns:ConceptList/ns:Concept'') AS ANS(concept);
					';
					EXECUTE sp_executesql @MonXml;
				 
				--Assignation des valeurs specifiques du JSON aux variables @Table, @JdvAns, @Name et @IgnoredValues
				SELECT @Table = tableName, @JdvAns = jeuDeValeursANS, @Name = name, @IgnoredValues = ignoredValues
				FROM OPENJSON (@JsonCursor) WITH (
					tableName NVARCHAR (MAX) '$.tableName',
					jeuDeValeursANS NVARCHAR (MAX) '$.jeuDeValeursANS',
					name NVARCHAR (500) '$.name',
					ignoredValues NVARCHAR(MAX) '$.ignoresValues' AS JSON);

				SET @SqlExtraValues = N'
					WITH recapExtraValues AS(
						SELECT 
							J.j_kprocess, 
							J.j_code, 
							J.j_code_system,
							J.j_toDelete,
							J.j_moveTo,
							COALESCE(J.is_ignored, 0) AS is_ignored,
							K.value AS k_values, 
							K.code AS k_code
						FROM OPENJSON(@JsonCursor, ''$.mapping'') 
							WITH (
								j_kprocess NVARCHAR(MAX) ''$.kprocess'', 
								j_code NVARCHAR(MAX) ''$.code'',
								j_code_system NVARCHAR(500) ''$.codeSystem'',
								j_toDelete NVARCHAR(500) ''$.toDelete'',
								j_moveTo NVARCHAR(MAX) ''$.moveTo'',
								is_ignored BIT ''$.ignore''
							) AS J
						FULL JOIN ' + @DatabaseName + '.' + @Table + ' AS K ON REPLACE(K.value,''.'','''') = REPLACE(J.j_kprocess, ''.'','''') 
						WHERE J.j_moveTo IS NULL)
						INSERT INTO #anomalies (profil, version, fichier_json_name, name, table_name, jeux_de_valeurs_name,
												j_kprocess, j_code, j_code_system,
												k_values, k_code, is_ignored, extra_value, to_delete)
							SELECT
								@Profile,
								@Version,
								@NomDeFichierJson, 
								@Name,
								@Table, 
								@JdvAns,
								j_kprocess,
								j_code, 
								j_code_system,
								k_values,
								k_code,
								is_ignored,
								CASE WHEN (k_values IS NOT NULL OR k_values !='''')
									AND (j_kprocess IS NULL OR j_code IS NULL)
									AND is_ignored = 0
									THEN 1 ELSE 0 
									END,
								CASE WHEN LOWER(TRIM(j_toDelete)) = ''true'' THEN 1 ELSE 0 END
							FROM recapExtraValues AS REV
							WHERE k_values IS NOT NULL
								AND (j_code IS NULL OR j_kprocess IS NULL)
								AND is_ignored = 0
								OR LOWER(TRIM(j_toDelete)) = ''true''
								; 
							';
				EXECUTE sp_executesql @SqlExtraValues, N'@JsonCursor NVARCHAR(MAX),
														@Profile NVARCHAR(MAX), 
														@Version NVARCHAR(MAX),
														@NomDeFichierJson NVARCHAR(MAX), 
														@Name NVARCHAR(500),
														@Table SYSNAME, 
														@JdvAns NVARCHAR(MAX)', 
														@JsonCursor = @JsonCursor, 
														@Profile = @Profile,
														@Version = @Version,
														@NomDeFichierJson = @NomDeFichierJson,
														@Name = @Name, 
														@Table = @Table,  
														@JdvAns = @JdvAns;

				SET @SqlToInsert = N'
							WITH recapToInsert AS(
								SELECT 
									J.j_kprocess, 
									J.j_code, 
									J.j_code_system,
									COALESCE(J.is_ignored, 0) AS is_ignored,
									J.j_additional_values,
									J.j_toDelete,
									K.value AS k_values, 
									K.code AS k_code
								FROM OPENJSON(@JsonCursor, ''$.mapping'') 
								WITH (
									j_kprocess NVARCHAR(MAX) ''$.kprocess'', 
									j_code NVARCHAR(MAX) ''$.code'',
									j_code_system NVARCHAR(500) ''$.codeSystem'',
									j_toDelete NVARCHAR(500) ''$.toDelete'',
									is_ignored BIT ''$.ignore'',
									j_additional_values NVARCHAR(MAX) ''$.additionalValues'' AS JSON
									) AS J
						
								FULL JOIN ' + @DatabaseName + '.' + @Table + ' AS K ON REPLACE(K.value,''.'','''') = REPLACE(J.j_kprocess, ''.'', '''')
							)
							INSERT INTO #anomalies(profil, version, fichier_json_name, name, table_name, jeux_de_valeurs_name, 
													j_kprocess, j_code, j_code_system,
													k_values, k_code, 
													is_ignored, to_insert, to_delete)
								SELECT
									@Profile,
									@Version,
									@NomDeFichierJson, 
									@Name,
									@Table, 
									@JdvAns,
									j_kprocess,
									j_code, 
									j_code_system,
									k_values,
									k_code,
									is_ignored,
									CASE WHEN (k_values IS NULL OR k_values ='''') 
											AND COALESCE(is_ignored, 0) = 0 
											AND (j_kprocess IS NOT NULL OR j_code IS NOT NULL)
												THEN 1 ELSE 0 END,
									CASE WHEN LOWER(TRIM(j_toDelete)) = ''true'' THEN 1 ELSE 0 END
								FROM recapToInsert AS RTI
								WHERE k_values IS NULL OR k_values = '''';
							';
				EXECUTE sp_executesql @SqlToInsert, N'@JsonCursor NVARCHAR(MAX),
													@Profile NVARCHAR(MAX), 
													@Version NVARCHAR(MAX),
													@NomDeFichierJson NVARCHAR(MAX), 
													@Name NVARCHAR(500),
													@Table SYSNAME, 
													@JdvAns NVARCHAR(MAX)', 
													@JsonCursor = @JsonCursor, 
													@Profile = @Profile,
													@Version = @Version,
													@NomDeFichierJson = @NomDeFichierJson,
													@Name = @Name, 
													@Table = @Table,  
													@JdvAns = @JdvAns;

				SET @SqlToMap = N'
					DROP TABLE IF EXISTS #ignoresValues;
					CREATE TABLE #ignoresValues(
						i_code NVARCHAR(50),
						i_code_system NVARCHAR(50)
					);
					INSERT INTO #ignoresValues (i_code, i_code_system)
						SELECT 
							i_code, 
							i_code_system
						FROM OPENJSON(@IgnoredValues)
						WITH (
							i_code NVARCHAR(MAX) ''$.code'',
							i_code_system NVARCHAR(500) ''$.codeSystem''
						);
					
					DROP TABLE IF EXISTS #jsonValues;
					CREATE TABLE #jsonValues(
						j_jdv_ANS NVARCHAR(MAX),
						j_kprocess NVARCHAR(50),
						j_code NVARCHAR(50), 
						j_code_system NVARCHAR(50),
						adv_code NVARCHAR(50), 
						adv_code_system NVARCHAR(50),
						to_ignore BIT
					);
					INSERT INTO #jsonValues(j_jdv_ANS,j_kprocess, j_code, j_code_system, adv_code, adv_code_system, to_ignore)
					SELECT @JdvAns,
						j.kprocess,
						j.code, 
						j.code_system,
						adv.code, 
						adv.code_system,
						ISNULL(j.ignore, CAST(0 AS BIT)) AS to_ignore
					FROM OPENJSON(@JsonCursor, ''$.mapping'')
					WITH (
						kprocess NVARCHAR(50) ''$.kprocess'',
						code NVARCHAR(50) ''$.code'',
						code_system NVARCHAR(50) ''$.codeSystem'',
						ignore BIT ''$.ignore'',
						additional_values NVARCHAR(MAX) ''$.additionalValues'' AS JSON
					)j
					OUTER APPLY OPENJSON(j.additional_values)
					WITH (
						code NVARCHAR(50) ''$.code'',
						code_system NVARCHAR(50) ''$.codeSystem''
						) adv;

					DROP TABLE IF EXISTS #recap;
					CREATE TABLE #recap(
						j_kprocess NVARCHAR(500),
						j_code NVARCHAR(500),
						j_code_system NVARCHAR(500),
						j_is_ignored BIT,
						adv_code NVARCHAR(500),
						adv_code_system NVARCHAR(500),
						x_code NVARCHAR(50),
						x_code_system NVARCHAR(50),
						i_code NVARCHAR(500),
						i_code_system NVARCHAR(500)
					);

					INSERT INTO #recap(j_kprocess, j_code, j_code_system, j_is_ignored, adv_code, adv_code_system, x_code, x_code_system, i_code, i_code_system)
						SELECT J.j_kprocess, 
							J.j_code, 
							J.j_code_system, 
							J.to_ignore,
							J.adv_code,
							J.adv_code_system,
							X.x_code, 
							X.x_code_system, 
							I.i_code,
							I.i_code_system
						FROM #jsonValues AS J
						FULL JOIN #valeurs_xml_ans AS X ON X.x_code = J.j_code
						LEFT JOIN #ignoresValues AS I ON X.x_code = I.i_code
						WHERE (J.to_ignore = 0 OR J.to_ignore IS NULL)
						AND (j_code IS NULL AND x_code IS NOT NULL)
						AND x_code NOT IN (SELECT i_code FROM #ignoresValues WHERE i_code IS NOT NULL) 
						AND x_code NOT IN (SELECT adv_code FROM #jsonValues WHERE adv_code IS NOT NULL)
						
						INSERT INTO #anomalies(profil, version, fichier_json_name, name, table_name, jeux_de_valeurs_name, 
											j_kprocess, j_code, j_code_system, j_ignored_values, j_additional_values,
											x_code, x_code_system,
											value_to_map)
						SELECT
							@Profile,
							@Version,
							@NomDeFichierJson, 
							@Name,
							@Table, 
							@JdvAns,
							R.j_kprocess, 
							R.j_code, 
							R.j_code_system, 
							R.j_is_ignored,
							R.adv_code,
							R.x_code, 
							R.x_code_system, 
							''1''
						FROM #recap AS R;
				';
				EXECUTE sp_executesql @SqlToMap, N'@JsonCursor NVARCHAR(MAX),
													@Profile NVARCHAR(MAX), 
													@Version NVARCHAR(MAX),
													@NomDeFichierJson NVARCHAR(MAX), 
													@Name NVARCHAR(500),
													@Table SYSNAME, 
													@JdvAns NVARCHAR(MAX), 
													@IgnoredValues NVARCHAR(MAX)',
													@JsonCursor = @JsonCursor, 
													@Profile = @Profile,
													@Version = @Version,
													@NomDeFichierJson = @NomDeFichierJson,
													@Name = @Name, 
													@Table = @Table,  
													@JdvAns = @JdvAns,
													@IgnoredValues = @IgnoredValues
													;

				SET @SqlMoveTo = N'
					WITH recapToMove AS(
						SELECT 
							J.j_kprocess,
							J.j_moveTo,
							K.value AS k_values, 
							K.code AS k_code
						FROM OPENJSON(@JsonCursor, ''$.mapping'') 
						WITH (
							j_kprocess NVARCHAR(MAX) ''$.kprocess'',
							j_moveTo NVARCHAR(MAX) ''$.moveTo''
							) AS J
						FULL JOIN ' + @DatabaseName + '.' + @Table + ' AS K ON REPLACE(K.value, ''.'', '''') = REPLACE(J.j_kprocess, ''.'', '''')
						LEFT JOIN ' + @DatabaseName + '.' + @Table + ' AS K2 ON REPLACE(K.value, ''.'', '''') = REPLACE(j_moveTo, ''.'', '''')
						)
							INSERT INTO #anomalies(profil, version, fichier_json_name, name, table_name, jeux_de_valeurs_name, 
													j_kprocess,
													k_values, k_code, 
													move_to)
								SELECT
									@Profile,
									@Version,
									@NomDeFichierJson, 
									@Name,
									@Table, 
									@JdvAns,
									j_kprocess,
									k_values,
									k_code,
									j_moveTo								
								FROM recapToMove AS RTM
								WHERE j_moveTo IS NOT NULL;				
								';
				EXECUTE sp_executesql @SqlMoveTo, N'@JsonCursor NVARCHAR(MAX),
													@Profile NVARCHAR(MAX), 
													@Version NVARCHAR(MAX),
													@NomDeFichierJson NVARCHAR(MAX), 
													@Name NVARCHAR(500),
													@Table SYSNAME, 
													@JdvAns NVARCHAR(MAX), 
													@IgnoredValues NVARCHAR(MAX)',
													@JsonCursor = @JsonCursor, 
													@Profile = @Profile,
													@Version = @Version,
													@NomDeFichierJson = @NomDeFichierJson,
													@Name = @Name, 
													@Table = @Table,  
													@JdvAns = @JdvAns,
													@IgnoredValues = @IgnoredValues;

				SET @SqlDoppelganger = N'
					WITH recapDoppelganger AS(
						SELECT 
							J.j_kprocess,
							COUNT(*) AS nbDoublon
						FROM OPENJSON(@JsonCursor, ''$.mapping'') 
						WITH (
							j_kprocess NVARCHAR(MAX) ''$.kprocess'',
							j_code NVARCHAR
							) AS J
						GROUP BY J.j_kprocess)

						INSERT INTO #anomalies(profil, version, fichier_json_name, name, table_name, jeux_de_valeurs_name, 
													j_kprocess,
													doppelganger)
								SELECT
									@Profile,
									@Version,
									@NomDeFichierJson, 
									@Name,
									@Table, 
									@JdvAns,
									j_kprocess,
									CASE WHEN nbDoublon > 1 THEN 1 ELSE 0 END							
								FROM recapDoppelganger AS RDG
								WHERE nbDoublon > 1 AND j_kprocess !='''';
				';


				EXECUTE sp_executesql @SqlDoppelganger, N'@JsonCursor NVARCHAR(MAX),
													@Profile NVARCHAR(MAX), 
													@Version NVARCHAR(MAX),
													@NomDeFichierJson NVARCHAR(MAX), 
													@Name NVARCHAR(500),
													@Table SYSNAME, 
													@JdvAns NVARCHAR(MAX)', 
													@JsonCursor = @JsonCursor, 
													@Profile = @Profile,
													@Version = @Version,
													@NomDeFichierJson = @NomDeFichierJson,
													@Name = @Name, 
													@Table = @Table,  
													@JdvAns = @JdvAns;

				FETCH NEXT FROM foreach INTO @NomDeFichierJson;
			END

		CLOSE foreach;
		DEALLOCATE foreach;
		
		SELECT * FROM #anomalies ORDER BY fichier_json_name;

	END
GO