
Verificando conexión a la base de datos
  Conexión exitosa a la base de datos (mysql-dbcentral_db:3306)
[critical] Error thrown while running command "doctrine:database:create --if-not-exists". Message: "An exception occurred in the driver: SQLSTATE[HY000] [1044] Access denied for user 'desarrollador'@'%' to database 'mrv'"

In ExceptionConverter.php line 91:
                                                                                                                            
  An exception occurred in the driver: SQLSTATE[HY000] [1044] Access denied for user 'desarrollador'@'%' to database 'mrv'  
                                                                                                                            

In Exception.php line 24:
                                                                                       
  SQLSTATE[HY000] [1044] Access denied for user 'desarrollador'@'%' to database 'mrv'  
                                                                                       

In PDOConnect.php line 28:
                                                                                       
  SQLSTATE[HY000] [1044] Access denied for user 'desarrollador'@'%' to database 'mrv'  
                                                                                       

doctrine:database:create [-c|--connection CONNECTION] [--if-not-exists]

