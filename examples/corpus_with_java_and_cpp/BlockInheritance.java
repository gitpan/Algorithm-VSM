// This code example is from the following source:
//
// Book Title:  Programming with Objects, A Comparative Presentation
//              of Object Oriented Programming with C++ and Java
//
// Chapter:     Chapter 3 ---- The Notion Of A Class And Some Other Key Ideas
//
// Section:     Section 3.6 -- Blocking Inheritance
//
// The links to the rest of the code in this book are at
//     
//      http://programming-with-objects.com/pwocode.html
//
// For further information regarding the book, please visit
//
//      http://programming-with-objects.com
//




//BlockInheritance.java

class User {      
    private String name;
    private int age;
    public User( String str, int yy ) { name = str;  age = yy; } 
    public void print() { 
        System.out.print( "name: " + name + "  age: " + age ); 
    }
}

//StudentUser cannot be extended
final class StudentUser extends User {                            //(A)
    private String schoolEnrolled;
    public StudentUser( String nam, int y, String sch ) {
        super(nam, y);
        schoolEnrolled = sch;
    }
    public void print() {
        super.print();
        System.out.println( "  school: " + schoolEnrolled );
    }
}

//Wrong:
//class UndergradStudentUser extends StudentUser { }              //(B)

class Test {
    public static void main( String[] args ) {
        StudentUser us = new StudentUser( 
                           "Zaphlet", 10, "Cosmology" );
        us.print();
    }
}