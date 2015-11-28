<?php
/**
 * This is the single include file required for using iveeCrest in applications or scripts. All other required classes
 * are loaded via autoloader.
 *
 * PHP version 5.4
 *
 * @category IveeCrest
 * @package  IveeCrestInit
 * @author   Aineko Macx <ai@sknop.net>
 * @license  https://github.com/aineko-m/iveeCrest/blob/master/LICENSE GNU Lesser General Public License
 * @link     https://github.com/aineko-m/iveeCrest/blob/master/iveeCrest/iveeCrestInit.php
 *
 */

//Check PHP version
if (version_compare(PHP_VERSION, '5.4') < 0)
    exit('PHP Version 5.4 or higher required. Currently ' . PHP_VERSION . PHP_EOL);

//Draconic edit: commented out, 64-bit php not possible on Win7?
//Check for 64 bit PHP
//Integers used in iveeCrest can easily exceed the maximum 2^31 of 32 bit PHP
//if (PHP_INT_SIZE < 8)
//    exit('64 bit PHP required. Currently ' . PHP_INT_SIZE * 8 . ' bit' . PHP_EOL);

//eve runs on UTC time
date_default_timezone_set('UTC');

//register iveeCrest's class loader
spl_autoload_register('iveeClassLoader');

/**
 * Auto class loader. Improved from http://www.php-fig.org/psr/psr-0/
 *
 * @param string $className the fully qualified class name. The loader relies on PSR compliant namespacing and class
 * file directory structuring to find and load the required files.
 *
 * @return void
 */
function iveeClassLoader($className)
{
    $className = ltrim($className, '\\');
    $fileName  = dirname(__FILE__) . DIRECTORY_SEPARATOR;
    $namespace = '';
    if ($lastNsPos = strrpos($className, '\\')) {
        $namespace = substr($className, 0, $lastNsPos);
        $className = substr($className, $lastNsPos + 1);
        $fileName  .= str_replace('\\', DIRECTORY_SEPARATOR, $namespace) . DIRECTORY_SEPARATOR;
    }
    $fileName .= str_replace('_', DIRECTORY_SEPARATOR, $className) . '.php';
    if(file_exists($fileName))
        require_once $fileName;
}